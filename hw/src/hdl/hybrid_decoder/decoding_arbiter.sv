`timescale 1ns / 1ps

import lynxTypes::*;

module decoding_arbiter #(
    parameter integer OUT_BYTE_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,
    
    input logic active,
    input logic mode, // 0 <> RLE, 1 <> BPE

    // Relay inputs and streams
    input logic [5:0] start, 
    input logic [3:0] bit_width, 
    input logic [30:0] run_length, 

    AXI4SC.s in, 
    AXI4SC.m out
);
    AXI4SC bpe_in(clk);
    AXI4SC bpe_out(clk);
    AXI4SC rle_in(clk);
    AXI4SC rle_out(clk);



    // Input AXI streams
    always_comb begin
        bpe_in.tdata = in.tdata;
        bpe_in.tkeep = in.tkeep;
        bpe_in.tlast = in.tlast;
        
        rle_in.tdata = in.tdata;
        rle_in.tkeep = in.tkeep;
        rle_in.tlast = in.tlast;

        bpe_in.tvalid = 1'b0;
        rle_in.tvalid = 1'b0;
        in.tready = 1'b0;
        if (active) begin
            if (mode) begin
                bpe_in.tvalid = in.tvalid;
                in.tready = bpe_in.tready;
            end else begin
                rle_in.tvalid = in.tvalid;
                in.tready = rle_in.tready;
            end
        end
    end

    // Output AXI stream
    always_comb begin
        out.tdata = 0;
        out.tkeep = 0;
        out.tlast = 1'b0; 
        out.tvalid = 1'b0;
        bpe_out.tready = 1'b0;
        rle_out.tready = 1'b0;
        if (active) begin
            if (mode) begin
                out.tdata = bpe_out.tdata;
                out.tkeep = bpe_out.tkeep;
                out.tlast = bpe_out.tlast;
                out.tvalid = bpe_out.tvalid;
                bpe_out.tready = out.tready;
            end else begin
                out.tdata = rle_out.tdata;
                out.tkeep = rle_out.tkeep;
                out.tlast = rle_out.tlast;
                out.tvalid = rle_out.tvalid;
                rle_out.tready = out.tready;
            end
        end
    end



    bitpacking_decoder #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) bpe_decoder (
        .clk(clk),
        .rst_n(rst_n),

        .start(start),
        .bit_width(bit_width),
        .run_length(run_length),

        .in(bpe_in),
        .out(bpe_out)
    );

    runlength_decoder #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) rle_decoder (
        .clk(clk),
        .rst_n(rst_n),

        .start(start),
        .bit_width(bit_width),
        .run_length(run_length),

        .in(rle_in),
        .out(rle_out)
    );
endmodule
