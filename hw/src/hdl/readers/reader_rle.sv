`timescale 1ns / 1ps

import lynxTypes::*;

module reader_rle (
    input logic clk,
    input logic rst_n,

    AXI4SC.s axis_host_recv,
    AXI4SC.m axis_host_send,

    // Debug outputs
    output logic [2:0] debug_state
);
    localparam OUT_BYTE_WIDTH = 1;
    localparam OUT_BIT_WIDTH = OUT_BYTE_WIDTH * 8;
    localparam OUT_VALUES = AXI_DATA_BITS / OUT_BIT_WIDTH;


    AXI4SC input_ff(clk);

    AXI4SC decoder_in(clk);
    AXI4SC decoder_out(clk);

    logic [2:0] state;
    // Index in the input chunk
    // logic [5:0] start;
    // Number of remaining values
    // Have to keep track because of BPE runs that might be padded producing slighly more values than expected
    reg [54:0] num_values;
    logic [54:0] num_values_comb;
    assign num_values_comb = (state == 2'd0) ? {23'd0, input_ff.tconfig[47:16]} : num_values;



    assign input_ff.tready = state == 2'd2 ? decoder_in.tready : 1'b0;

    assign decoder_in.tdata = input_ff.tdata;
    assign decoder_in.tkeep = input_ff.tkeep;
    assign decoder_in.tlast = input_ff.tlast;
    assign decoder_in.tvalid = state == 2'd2 ? input_ff.tvalid : 1'b0;

    assign decoder_out.tready = state >= 2'd2 ? axis_host_send.tready : 1'b0;

    assign axis_host_send.tdata = decoder_out.tdata;
    assign axis_host_send.tlast = num_values <= OUT_VALUES;
    assign axis_host_send.tvalid = state >= 2'd2 ? decoder_out.tvalid && num_values > 0 : 1'b0;

    // axis_host_send.tkeep
    always_comb begin
        for (int i = 0; i < OUT_VALUES; i++) begin
            axis_host_send.tkeep[i*OUT_BYTE_WIDTH+:OUT_BYTE_WIDTH] = {(OUT_BYTE_WIDTH){i < num_values ? 1'b1 : 1'b0}};
        end
    end
    
    always_ff @(posedge clk) begin
        if (rst_n) begin
            case (state)
                2'd0: begin
                    if (input_ff.tvalid) begin
                        // Read number of values and data start
                        num_values <= {23'd0, input_ff.tconfig[47:16]};
                        state <= 2'd2;
                    end
                end
                2'd2: begin
                    if (decoder_out.tready && decoder_out.tvalid) begin
                        num_values <= axis_host_send.tlast ? 55'd0 : num_values - OUT_VALUES;
                    end

                    if (decoder_in.tready && decoder_in.tvalid && decoder_in.tlast) begin
                        state <= 2'd3;
                    end
                end
                2'd3: begin
                    if (decoder_out.tready && decoder_out.tvalid) begin
                        num_values <= axis_host_send.tlast ? 55'd0 : num_values - OUT_VALUES;
                    end
                    
                    if (axis_host_send.tvalid && axis_host_send.tready && axis_host_send.tlast) begin
                        state <= 2'd0;
                    end
                end
                default: begin
                end
            endcase
        end else begin
            num_values <= 55'd0;
            state <= 2'd0;
        end
    end



    // Decoder for hybrid encoding
    header_reader #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) hybrid_decoder (
        .clk(clk),
        .rst_n(rst_n),

        .start(6'd1),
        .bit_width(4'b0001),

        .in(decoder_in),
        .out(decoder_out)
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
