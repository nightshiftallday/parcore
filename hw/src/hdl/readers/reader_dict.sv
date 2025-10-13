`timescale 1ns / 1ps

import lynxTypes::*;
import reader_pkg::*;

/*
    This reader module can handle Parquet data pages (v1.0) with a plain dictionary and hybrid encoded values
    (RLE_DICTIONARY) combined with Snappy compression. As is the case in a Parquet column chunk, the dictionary
    should be supplied first in a terminated stream. Afterwards an arbitrary number of data pages can be read.
    To write new dictionary content (for example when reading another row group) the module has to be reset.

    This modules does not work when there are NULL values in the data.
*/
module reader_dict #(
    parameter integer OUT_BYTE_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    AXI4SC.s axis_host_recv,
    AXI4SC.m axis_host_send,

    // Debug outputs
    output logic [2:0] debug_state
);
    localparam OUT_BIT_WIDTH = OUT_BYTE_WIDTH * 8;
    localparam OUT_VALUES = AXI_DATA_BITS / OUT_BIT_WIDTH;

    AXI4SC input_ff(clk);

    AXI4SC decoder_in(clk);
    AXI4SC decoder_out(clk);
    AXI4SC mapper_in(clk);
    AXI4SC mapper_out(clk);

    logic [2:0] state;
    // Index in the input chunk
    // logic [5:0] start;
    logic [3:0] bit_width;
    logic [3:0] bit_width_comb;
    assign bit_width_comb = (state == 3'd1) ? input_ff.tdata[3:0] : bit_width;
    // Number of remaining values
    // Have to keep track because of BPE runs that might be padded producing slighly more values than expected
    reg [54:0] num_values;
    logic [54:0] num_values_comb;
    assign num_values_comb = (state == 3'd1) ? {23'd0, input_ff.tconfig[47:16]} : num_values;

    logic need_reset;

    assign decoder_in.tdata = input_ff.tdata;
    assign decoder_in.tkeep = input_ff.tkeep;
    assign decoder_in.tlast = input_ff.tlast;

    assign decoder_out.tready = state >= 3'd1 ? mapper_in.tready : 1'b0;

    assign mapper_in.tdata = state == 3'd0 ? input_ff.tdata : decoder_out.tdata;
    assign mapper_in.tkeep = state == 3'd0 ? input_ff.tkeep : decoder_out.tkeep;
    assign mapper_in.tlast = state == 3'd0 ? input_ff.tlast : decoder_out.tlast;
    

    assign mapper_out.tready = axis_host_send.tready;

    assign axis_host_send.tdata = mapper_out.tdata;
    assign axis_host_send.tlast = (state == 3'd0) ? 1'b0 : num_values_comb <= OUT_VALUES;

    // axis_host_send.tkeep
    always_comb begin
        for (int i = 0; i < OUT_VALUES; i++) begin
            axis_host_send.tkeep[i*OUT_BYTE_WIDTH+:OUT_BYTE_WIDTH] = {(OUT_BYTE_WIDTH){i < num_values_comb ? 1'b1 : 1'b0}};
        end
    end

    // input_ff.tready, mapper_in.tvalid and axis_host_send.tvalid
    always_comb begin
        input_ff.tready = 1'b0;
        mapper_in.tvalid = 1'b0;
        decoder_in.tvalid = 1'b0;
        input_ff.tready = 1'b0;
        axis_host_send.tvalid = 1'b0;
        if (rst_n) begin
            if (state == 3'd0) begin
                // Route input to mapper
                input_ff.tready = mapper_in.tready;
                mapper_in.tvalid = input_ff.tvalid;
            end else if (state == 3'd1) begin
                // Route fifo output to decoder
                input_ff.tready = decoder_in.tready;
                decoder_in.tvalid = input_ff.tvalid;
                mapper_in.tvalid = decoder_out.tvalid;
            end else if (state == 3'd3) begin
                // Route fifo output to decoder
                input_ff.tready = decoder_in.tready;
                decoder_in.tvalid = input_ff.tvalid;
                mapper_in.tvalid = decoder_out.tvalid;
            end

            if (state >= 3'd1) begin
                axis_host_send.tvalid = mapper_out.tvalid && num_values_comb > 0;
            end
        end
    end
    
    // State machine
    always_ff @(posedge clk) begin
        if (rst_n) begin
            case (state)
                3'd0: begin
                    // Write dictionary
                    if (input_ff.tready && input_ff.tvalid && input_ff.tlast) begin
                        state <= 3'd1;
                    end
                end
                3'd1: begin
                    if (input_ff.tvalid) begin
                        // Read number of values and data start
                        // start <= 1; // 1 for (bit_width)

                        // TODO: handle case where varint encoded size is present in data section
                        num_values <= {23'd0, input_ff.tconfig[47:16]};
                        bit_width <= input_ff.tdata[3:0];
                        state <= 3'd3;
                    end
                end
                3'd3: begin
                    if (mapper_out.tready && mapper_out.tvalid) begin
                        num_values <= axis_host_send.tlast ? 55'd0 : num_values_comb - OUT_VALUES;
                    end

                    if (decoder_in.tready && decoder_in.tvalid && decoder_in.tlast) begin
                        need_reset <= input_ff.tconfig[0];
                        state <= 3'd4;
                    end
                end
                3'd4: begin
                    if (mapper_out.tready && mapper_out.tvalid) begin
                        num_values <= axis_host_send.tlast ? 55'd0 : num_values_comb - OUT_VALUES;
                    end
                    
                    if (axis_host_send.tvalid && axis_host_send.tready && axis_host_send.tlast) begin
                        if (need_reset) begin
                            state <= 3'd5;
                        end else begin
                            state <= 3'd1;
                        end
                    end
                end
                3'd5: begin
                    //Internal reset
                    num_values <= 55'd0;
                    bit_width <= 4'd0;
                    need_reset <= 1'b0;
                    state <= 3'd0;
                end
                default: ;
            endcase
        end else begin
            state <= 3'd0;
            need_reset <= 1'b0;
        end
    end



    // Submodule instantiations
    header_reader #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) hybrid_decoder (
        .clk(clk),
        .rst_n(rst_n && state != 3'd5),

        .start(6'd1),
        .bit_width(bit_width_comb),

        .in(decoder_in),
        .out(decoder_out)
    );

    dictionary_decoder #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) dictionary_mapper (
        .clk(clk),
        .rst_n(rst_n && state != 3'd5),

        .mode(state == 0),

        .in(mapper_in),
        .out(mapper_out)
    );

        OverflowRegister input_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in(axis_host_recv),
        .out(input_ff)
    );

    // Debug outputs
    assign debug_state = state;

endmodule
