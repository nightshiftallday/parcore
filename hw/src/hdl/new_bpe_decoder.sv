`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"
`include "parcore_types.svh"

import lynxTypes::*;
import parcore::bpe_metadata_t;

// NOTE: only the first `in_meta.data.bit_width` * NUM_ELEMENTS bits are read
// from the `in` input stream.
//
// TODO: we can optimize the number of bits in the input, since bit_width is at most 15 bits.

module ExpandBPE #(
    parameter type data_t,
    parameter NUM_ELEMENTS
) (
    input logic clk,
    input logic rst_n,

    valid_i.s in_meta, // #(bpe_metadata_t)
    data_i.s in,       // #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0])

    ndata_i out   // #(data_t, NUM_ELEMENTS)
);

// Extracting data from the data_i interface
logic [$bits(data_t) * NUM_ELEMENTS - 1:0] in_data;
bpe_metadata_t in_meta_data;

assign in_data = in.data;
assign in_meta_data = in_meta.data;

// ready chaining
assign in.ready = in_meta.valid && out.ready;

// Driving output based on the current intrenal state
always_comb begin
    out.valid = in_meta.valid && in.valid;
    out.last = in.last;
    for (int i = 0; i < NUM_ELEMENTS; i++) begin
        out.data[i] = '0;
        for (int j = 0; j < in_meta_data.bit_width; j++) begin
            out.data[i][j] = in_data[i*in_meta_data.bit_width+j];
        end
        out.keep[i] = i < in_meta_data.count;
    end
end

endmodule
