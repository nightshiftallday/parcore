#!/usr/bin/env python3
"""Writes variants/v<N>_<name>.sv: TypedNDataSkidBuffer implementations that differ only in how the
element type of the typed_ndata_i port is obtained (and, for the flat variants, in the type handed
to ready_valid_i)."""
from pathlib import Path

TEMPLATE = """`timescale 1ns / 1ps

import libstf::type_t;

// Variant {name}: {doc}
module TypedNDataSkidBuffer #(
    parameter DATABEAT_SIZE
) (
    input logic clk,
    input logic rst_n,

    typed_ndata_i.s in, // #(DATABEAT_SIZE)
    typed_ndata_i.m out // #(DATABEAT_SIZE)
);

{decl}

typedef struct packed {{
    {field} data;
    type_t typ;
    logic[DATABEAT_SIZE - 1:0] keep;
    logic last;
}} tmp_t;

{wire}

ready_valid_i #(wire_t) skid_in(clk, rst_n), skid_out(clk, rst_n);
tmp_t in_packed, out_packed;

assign in_packed.data = in.data;
assign in_packed.typ  = in.typ;
assign in_packed.keep = in.keep;
assign in_packed.last = in.last;
assign skid_in.data   = wire_t'(in_packed);
assign skid_in.valid  = in.valid;
assign in.ready       = skid_in.ready;

SkidBuffer #(
    .data_t(wire_t)
) inst_skid_buffer (
    .clk(clk),
    .rst_n(rst_n),

    .in(skid_in),
    .out(skid_out)
);

assign out_packed     = tmp_t'(skid_out.data);
assign out.data       = out_packed.data;
assign out.typ        = out_packed.typ;
assign out.keep       = out_packed.keep;
assign out.last       = out_packed.last;
assign out.valid      = skid_out.valid;
assign skid_out.ready = out.ready;

endmodule
"""

STRUCT = "typedef tmp_t wire_t;"
FLAT = "typedef logic [$bits(tmp_t) - 1:0] wire_t;"

VARIANTS = [
    ("v1_typedef", "typedef in.data_t data_t (as in libstf)",
     "typedef in.data_t data_t;", "data_t[DATABEAT_SIZE - 1:0]", STRUCT),
    ("v2_localparam_type", "localparam type from the interface",
     "localparam type elem_t = in.data_t;", "elem_t[DATABEAT_SIZE - 1:0]", STRUCT),
    ("v3_type_op_element", "type() operator on one element",
     "typedef type(in.data[0]) elem_t;", "elem_t[DATABEAT_SIZE - 1:0]", STRUCT),
    ("v4_type_op_field", "type() operator on the whole data field",
     "", "type(in.data)", STRUCT),
    ("v5_direct_field", "in.data_t used directly in the struct",
     "", "in.data_t[DATABEAT_SIZE - 1:0]", STRUCT),
    ("v6_typedef_flat", "typedef in.data_t, flat vector handed to ready_valid_i",
     "typedef in.data_t data_t;", "data_t[DATABEAT_SIZE - 1:0]", FLAT),
    ("v7_bits_width", "width from $bits (no type from the interface)",
     "typedef logic [$bits(in.data) / DATABEAT_SIZE - 1:0] elem_t;", "elem_t[DATABEAT_SIZE - 1:0]",
     STRUCT),
    ("v8_localparam_flat", "localparam type from the interface, flat vector to ready_valid_i",
     "localparam type elem_t = in.data_t;", "elem_t[DATABEAT_SIZE - 1:0]", FLAT),
    ("v9_type_op_flat", "type() operator on one element, flat vector to ready_valid_i",
     "typedef type(in.data[0]) elem_t;", "elem_t[DATABEAT_SIZE - 1:0]", FLAT),
    ("v10_typedef_renamed", "typedef in.data_t under a different name",
     "typedef in.data_t elem_t;", "elem_t[DATABEAT_SIZE - 1:0]", STRUCT),
    ("v11_localparam_same_name", "localparam type from the interface, named data_t",
     "localparam type data_t = in.data_t;", "data_t[DATABEAT_SIZE - 1:0]", STRUCT),
]


def main():
    out = Path(__file__).parent / "variants"
    out.mkdir(exist_ok=True)
    for name, doc, decl, field, wire in VARIANTS:
        (out / f"{name}.sv").write_text(
            TEMPLATE.format(name=name, doc=doc, decl=decl, field=field, wire=wire))


if __name__ == "__main__":
    main()
