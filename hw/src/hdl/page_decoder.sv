`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"
`include "parcore_types.svh"

import lynxTypes::*;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

module PageDecoder #(
    parameter NUM_BYTES = AXI_DATA_BITS / 8,
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_meta, // #(page_metadata_t)
    ndata_i.s in,            // #(data8_t, NUM_BYTES)

    ndata_i.m out            // #(data_t, NUM_ELEMENTS)
);

endmodule
