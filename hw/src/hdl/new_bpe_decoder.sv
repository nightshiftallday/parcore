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
    valid_i.s in_meta, // #(bpe_metadata_t)
    data_i.s in,       // #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0])

    ndata_i.m out      // #(data_t, NUM_ELEMENTS)
);

// Extracting data from the data_i interface
logic [$bits(data_t) * NUM_ELEMENTS - 1:0] in_data;
bpe_metadata_t in_meta_data;

assign in_data = in.data;
assign in_meta_data = in_meta.data;

assign in.ready = in_meta.valid && out.ready; // ready chaining

// Driving output based on the current intrenal state
assign out.valid = in_meta.valid && in.valid;
assign out.last = in.last;
generate
for (genvar I = 0; I < NUM_ELEMENTS; I++) begin
    for (genvar J = 0; J < $bits(data_t); J++) begin
        assign out.data[I][J] = J < in_meta_data.bit_width ?  in_data[I*in_meta_data.bit_width+J] : 0;
    end
    assign out.keep[I] = I < in_meta_data.count;
end
endgenerate

endmodule
