`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;
import libstf::data8_t;
import libstf::data32_t;

// This module reads the first 4 bytes of the input as an uint32, call it n.
// Then, it computes the offset n+4 and takes in as much input as needed to
// obtain a databeat where the byte at n+4+1 is valid.
//
// TODO: from state machine
module PageDecoder #(
    parameter type data_t,
    parameter NUM_ELEMENTS,
    parameter NUM_BYTES = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ndata_i.s in, // #(data8_t, NUM_BYTES)
    ndata_i.m out // #(data_t, NUM_ELEMENTS)
);



endmodule
