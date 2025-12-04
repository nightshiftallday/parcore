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

    tagged_i.s in, // #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t))
    ndata_i.m out  // #(data_t, NUM_ELEMENTS)
);

ndata_i #(data_t, NUM_ELEMENTS) out_inner ();

// Computing the next output combinatorially based on the current input.
ExpandBPECombinatorial #(data_t, NUM_ELEMENTS) inst_expand_bpe_combinatorial (
    .in(in),
    .out(out_inner)
);

// If the current input is valid this is then asynchronously assigned to the
// actual out to break the critical path.
NDataSkidBuffer #(data_t, NUM_ELEMENTS) inst_skid_buffer (
    .clk(clk),
    .rst_n(rst_n),

    .in(out_inner),
    .out(out)
);

endmodule

module ExpandBPECombinatorial #(
    parameter type data_t,
    parameter NUM_ELEMENTS
) (
    tagged_i.s in, // #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t))
    ndata_i.m out  // #(data_t, NUM_ELEMENTS)
);

bpe_metadata_t meta;
assign meta = in.tag;

assign out.last = meta.count <= NUM_ELEMENTS;
generate
for (genvar I = 0; I < NUM_ELEMENTS; I++) begin
    for (genvar J = 0; J < $bits(data_t); J++) begin
        assign out.data[I][J] = J < meta.bit_width ?  in.data[I*meta.bit_width+J] : 0;
    end
    assign out.keep[I] = I < meta.count;
end
endgenerate

assign out.valid = in.valid;
assign in.ready = out.ready; // ready chaining

endmodule
