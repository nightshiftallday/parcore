`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;

module reader_snappy (
    input logic clk,
    input logic rst_n,

    AXI4SR.s axis_host_recv,
    AXI4SR.m axis_host_send
);
    AXI4SC decompressor_in(clk);
    AXI4SC decompressor_out(clk);



    `AXIS_ASSIGN(axis_host_recv, decompressor_in)
    `AXIS_ASSIGN(decompressor_out, axis_host_send)



    // Snappy decompressor
    vhsnunzip_wrapper snappy_decompressor (
        .clk(clk),
        .rst_n(rst_n),

        .in(decompressor_in),
        .out(decompressor_out)
    );
endmodule
