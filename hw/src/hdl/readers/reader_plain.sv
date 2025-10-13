`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;

module reader_plain (
    input logic clk,
    input logic rst_n,

    AXI4SC.s axis_host_recv,
    AXI4SC.m axis_host_send
);
    `AXIS_ASSIGN(axis_host_recv, axis_host_send)
endmodule
