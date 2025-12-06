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

tagged_i #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t)) in_inner ();
tagged_i #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t)) middle_in (), middle_out ();
ndata_i #(data_t, NUM_ELEMENTS) out_inner ();

TaggedSkidBuffer #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t)) inst_in_skid_buffer (
    .clk(clk),
    .rst_n(rst_n),

    .in(in),
    .out(in_inner)
);

// Computing the next output combinatorially based on the current input.
ExpandBPECombinatorial1 #(data_t, NUM_ELEMENTS) inst_expand_bpe_combinatorial1 (
    .in(in_inner),
    .out(middle_in)
);

TaggedSkidBuffer #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t)) inst_middle_skid_buffer (
    .clk(clk),
    .rst_n(rst_n),

    .in(middle_in),
    .out(middle_out)
);

// Computing the next output combinatorially based on the current input.
ExpandBPECombinatorial2 #(data_t, NUM_ELEMENTS) inst_expand_bpe_combinatorial2 (
    .in(middle_out),
    .out(out_inner)
);

// If the current input is valid this is then asynchronously assigned to the
// actual out to break the critical path.
NDataSkidBuffer #(data_t, NUM_ELEMENTS) inst_out_skid_buffer (
    .clk(clk),
    .rst_n(rst_n),

    .in(out_inner),
    .out(out)
);

endmodule

module ExpandBPECombinatorial1 #(
    parameter type data_t,
    parameter NUM_ELEMENTS
) (
    tagged_i.s in, // #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t))
    tagged_i.m out  // #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t))
);

bpe_metadata_t meta;
assign meta = in.tag;

generate
for (genvar I = 0; I < NUM_ELEMENTS; I++) begin
    for (genvar J = 0; J < $bits(data_t); J++) begin
        // Note: The selection is done, but the final zero-padding check (J < meta.bit_width) is deferred to Stage 2.
        assign out.data[I * $bits(data_t) + J] = in.data[I*meta.bit_width+J];
    end
end
endgenerate

assign out.tag = in.tag;
assign out.valid = in.valid;
assign in.ready = out.ready; // ready chaining

endmodule

module ExpandBPECombinatorial2 #(
    parameter type data_t,
    parameter NUM_ELEMENTS
) (
    tagged_i.s in, // #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], NUM_ELEMENTS, $bits(bpe_metadata_t))
    ndata_i.m out  // #(data_t, NUM_ELEMENTS)
);

bpe_metadata_t meta;
assign meta = in.tag;

assign out.last = meta.count <= NUM_ELEMENTS;
for (genvar I = 0; I < NUM_ELEMENTS; I++) begin
    for (genvar J = 0; J < $bits(data_t); J++) begin
        // Mask the input
        assign out.data[I][J] = J < meta.bit_width ? in.data[I * $bits(data_t) + J] : 0;
    end
    assign out.keep[I] = I < meta.count;
end

assign out.valid = in.valid;
assign in.ready = out.ready; // ready chaining

endmodule
