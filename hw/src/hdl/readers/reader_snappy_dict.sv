`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;

/*
    This reader module can handle Parquet data pages (v1.0) with a plain dictionary and hybrid encoded values
    (RLE_DICTIONARY) combined with Snappy compression. As is the case in a Parquet column chunk, the dictionary
    should be supplied first in a terminated stream. Afterwards an arbitrary number of data pages can be read.
    To write new dictionary content (for example when reading another row group) the module has to be reset.

    This modules does not work when there are NULL values in the data.
*/
module reader_snappy_dict #(
    parameter integer OUT_BYTE_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    AXI4SR.s axis_host_recv,
    AXI4SR.m axis_host_send
);
    localparam OUT_BIT_WIDTH = OUT_BYTE_WIDTH * 8;
    localparam OUT_VALUES = AXI_DATA_BITS / OUT_BIT_WIDTH;



    AXI4SC decompressor_in(clk);
    AXI4SC decompressor_out(clk);
    AXI4SC decoder_in(clk);
    AXI4SC decoder_out(clk);
    AXI4SC mapper_in(clk);
    AXI4SC mapper_out(clk);

    logic [2:0] state;
    // Index in the input chunk
    logic [5:0] start;
    logic [3:0] bit_width;
    // Number of remaining values
    // Have to keep track because of BPE runs that might be padded producing slighly more values than expected
    logic [54:0] num_values;



    `AXIS_ASSIGN(axis_host_recv, decompressor_in)

    assign decoder_in.tdata = decompressor_out.tdata;
    assign decoder_in.tkeep = decompressor_out.tkeep;
    assign decoder_in.tlast = decompressor_out.tlast;
    assign decoder_in.tvalid = state == 3'd3 ? decompressor_out.tvalid : 1'b0;

    assign decoder_out.tready = state >= 3'd3 ? mapper_in.tready : 1'b0;

    assign mapper_in.tdata = state == 3'd0 ? decompressor_out.tdata : decoder_out.tdata;
    assign mapper_in.tkeep = state == 3'd0 ? decompressor_out.tkeep : decoder_out.tkeep;
    assign mapper_in.tlast = state == 3'd0 ? decompressor_out.tlast : decoder_out.tlast;
    
    assign mapper_out.tready = axis_host_send.tready;

    assign axis_host_send.tdata = mapper_out.tdata;
    assign axis_host_send.tlast = num_values <= OUT_VALUES;

    // axis_host_send.tkeep
    always_comb begin
        for (int i = 0; i < OUT_VALUES; i++) begin
            axis_host_send.tkeep[i*OUT_BYTE_WIDTH+:OUT_BYTE_WIDTH] = {(OUT_BYTE_WIDTH){i < num_values ? 1'b1 : 1'b0}};
        end
    end

    // decompressor_out.tready, mapper_in.tvalid and axis_host_send.tvalid
    always_comb begin
        decompressor_out.tready = 1'b0;
        mapper_in.tvalid = 1'b0;
        axis_host_send.tvalid = 1'b0;
        if (rst_n) begin
            if (state == 3'd0) begin
                decompressor_out.tready = mapper_in.tready;
                mapper_in.tvalid = decompressor_out.tvalid;
            end else if (state == 3'd3) begin
                decompressor_out.tready = decoder_in.tready;
                mapper_in.tvalid = decoder_out.tvalid;
            end

            if (state >= 3'd3) begin
                axis_host_send.tvalid = mapper_out.tvalid && num_values > 0;
            end
        end
    end
    
    // State machine
    always_ff @(posedge clk) begin
        if (rst_n) begin
            case (state)
                3'd0: begin
                    // Write dictionary
                    if (decompressor_out.tready && decompressor_out.tvalid && decompressor_out.tlast) begin
                        state <= 3'd1;
                    end
                end
                3'd1: begin
                    if (decompressor_out.tvalid) begin
                        // Read number of values and data start
                        start <= decompressor_out.tdata[5:0] + 5; // + 4 (def levels length) + 1 (bit_width)

                        // Read total value count from header of RLE block for def levels
                        // assuming that definition levels are a single RLE block
                        num_values[5:0] <= decompressor_out.tdata[38:33];
                        num_values[12:6] <= decompressor_out.tdata[46:40];
                        num_values[19:13] <= decompressor_out.tdata[54:48];
                        num_values[26:20] <= decompressor_out.tdata[62:56];
                        num_values[33:27] <= decompressor_out.tdata[70:64];
                        num_values[40:34] <= decompressor_out.tdata[78:72];
                        num_values[47:41] <= decompressor_out.tdata[86:80];
                        num_values[54:48] <= decompressor_out.tdata[94:88];

                        state <= 3'd2;
                    end
                end
                3'd2: begin
                    bit_width <= decompressor_out.tdata[(start-1)*8+:4];

                     // Unset header bytes according to def level size
                    if (start < 8) begin
                        num_values[12:6] <= 7'd0;
                    end
                    if (start < 9) begin
                        num_values[19:13] <= 7'd0;
                    end
                    if (start < 10) begin
                        num_values[26:20] <= 7'd0;
                    end
                    if (start < 11) begin
                        num_values[33:27] <= 7'd0;
                    end
                    if (start < 12) begin
                        num_values[40:34] <= 7'd0;
                    end
                    if (start < 13) begin
                        num_values[47:41] <= 7'd0;
                    end
                    if (start < 14) begin
                        num_values[54:48] <= 7'd0;
                    end

                    state <= 3'd3;
                end
                3'd3: begin
                    if (mapper_out.tready && mapper_out.tvalid) begin
                        num_values <= axis_host_send.tlast ? 55'd0 : num_values - OUT_VALUES;
                    end

                    if (decoder_in.tready && decoder_in.tvalid && decoder_in.tlast) begin
                        state <= 3'd4;
                    end
                end
                3'd4: begin
                    if (mapper_out.tready && mapper_out.tvalid) begin
                        num_values <= axis_host_send.tlast ? 55'd0 : num_values - OUT_VALUES;
                    end
                    
                    if (decompressor_out.tvalid) begin
                        state <= 3'd1;
                    end
                end
            endcase
        end else begin
            state <= 3'd0;
        end
    end



    // Submodule instantiations
    vhsnunzip_wrapper snappy_decompressor (
        .clk(clk),
        .rst_n(rst_n),

        .in(decompressor_in),
        .out(decompressor_out)
    );

    header_reader #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) hybrid_decoder (
        .clk(clk),
        .rst_n(rst_n),

        .start(start),
        .bit_width(bit_width),

        .in(decoder_in),
        .out(decoder_out)
    );

    dictionary_decoder #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) dictionary_mapper (
        .clk(clk),
        .rst_n(rst_n),

        .mode(state == 0),

        .in(mapper_in),
        .out(mapper_out)
    );
endmodule
