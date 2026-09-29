`timescale 1ns / 1ps

import libstf::*;

// Flat-port wrapper so Vivado can elaborate TypedDictionary2, whose TypedNDataSkidBuffers see the
// id interface through TypedDictionary2's ports.
module td2_syn_top (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic [63:0][7:0]             in_values_data,
    input  logic [63:0]                  in_values_keep,
    input  logic                         in_values_last,
    input  logic                         in_values_valid,
    output logic                         in_values_ready,

    input  logic [15:0][17:0]            in_ids_data,
    input  logic [$bits(type_t)-1:0]     in_ids_typ,
    input  logic [15:0]                  in_ids_keep,
    input  logic                         in_ids_last,
    input  logic                         in_ids_valid,
    output logic                         in_ids_ready,

    output logic [63:0][7:0]             out_data,
    output logic [$bits(type_t)-1:0]     out_typ,
    output logic [63:0]                  out_keep,
    output logic                         out_last,
    output logic                         out_valid,
    input  logic                         out_ready
);

typedef logic [17:0] id_t;

ndata_i       #(data8_t, 64) in_values (.clk(clk), .rst_n(rst_n));
typed_ndata_i #(16, id_t)    in_ids    (.clk(clk), .rst_n(rst_n));
typed_ndata_i #(64)          out       (.clk(clk), .rst_n(rst_n));

assign in_values.data  = in_values_data;
assign in_values.keep  = in_values_keep;
assign in_values.last  = in_values_last;
assign in_values.valid = in_values_valid;
assign in_values_ready = in_values.ready;

assign in_ids.data     = in_ids_data;
assign in_ids.typ      = type_t'(in_ids_typ);
assign in_ids.keep     = in_ids_keep;
assign in_ids.last     = in_ids_last;
assign in_ids.valid    = in_ids_valid;
assign in_ids_ready    = in_ids.ready;

assign out_data        = out.data;
assign out_typ         = out.typ;
assign out_keep        = out.keep;
assign out_last        = out.last;
assign out_valid       = out.valid;
assign out.ready       = out_ready;

TypedDictionary2 #(
    .id_t          (id_t),
    .DATABEAT_SIZE (64),
    .NUM_ELEMENTS  (16)
) inst_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_values (in_values),
    .in_ids    (in_ids),
    .out       (out)
);

endmodule
