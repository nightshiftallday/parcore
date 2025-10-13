`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;

module reader_snappy_rle (
    input logic clk,
    input logic rst_n,

    AXI4SR.s axis_host_recv,
    AXI4SR.m axis_host_send
);
    localparam OUT_BYTE_WIDTH = 1;
    localparam OUT_BIT_WIDTH = OUT_BYTE_WIDTH * 8;
    localparam OUT_VALUES = AXI_DATA_BITS / OUT_BIT_WIDTH;



    AXI4SC decompressor_in(clk);
    AXI4SC decompressor_out(clk);
    AXI4SC decoder_in(clk);
    AXI4SC decoder_out(clk);

    logic [1:0] state;
    // Index in the input chunk
    logic [5:0] start;
    // Number of remaining values
    // Have to keep track because of BPE runs that might be padded producing slighly more values than expected
    logic [54:0] num_values;



    `AXIS_ASSIGN(axis_host_recv, decompressor_in)

    assign decompressor_out.tready = state == 2'd2 ? decoder_in.tready : 1'b0;

    assign decoder_in.tdata = decompressor_out.tdata;
    assign decoder_in.tkeep = decompressor_out.tkeep;
    assign decoder_in.tlast = decompressor_out.tlast;
    assign decoder_in.tvalid = state == 2'd2 ? decompressor_out.tvalid : 1'b0;

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
                    if (decompressor_out.tvalid) begin
                        // Read number of values and data start
                        start <= decompressor_out.tdata[5:0] + 8; // + 4 (def levels length) + 4 (encoded length)

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

                        state <= 2'd1;
                    end
                end
                2'd1: begin
                     // Unset header bytes according to def level size
                    if (start < 11) begin
                        num_values[12:6] <= 7'd0;
                    end
                    if (start < 12) begin
                        num_values[19:13] <= 7'd0;
                    end
                    if (start < 13) begin
                        num_values[26:20] <= 7'd0;
                    end
                    if (start < 14) begin
                        num_values[33:27] <= 7'd0;
                    end
                    if (start < 15) begin
                        num_values[40:34] <= 7'd0;
                    end
                    if (start < 16) begin
                        num_values[47:41] <= 7'd0;
                    end
                    if (start < 17) begin
                        num_values[54:48] <= 7'd0;
                    end

                    state <= 2'd2;
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
                    
                    if (decompressor_out.tvalid) begin
                        state <= 2'd0;
                    end
                end
            endcase
        end else begin
            state <= 2'd0;
        end
    end



    // Snappy decompressor
    vhsnunzip_wrapper snappy_decompressor (
        .clk(clk),
        .rst_n(rst_n),

        .in(decompressor_in),
        .out(decompressor_out)
    );

    // Decoder for hybrid encoding
    header_reader #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) hybrid_decoder (
        .clk(clk),
        .rst_n(rst_n),

        .start(start),
        .bit_width(4'b0001),

        .in(decoder_in),
        .out(decoder_out)
    );
endmodule
