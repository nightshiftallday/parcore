`timescale 1ns / 1ps

import libstf::*;

// Flat-port wrapper so Vivado can elaborate TypedNDataSkidBuffer with an 18-bit element type and a
// packed struct element type.
module syn_top (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic [3:0][17:0]             a_in_data,
    input  logic [$bits(type_t)-1:0]     a_in_typ,
    input  logic [3:0]                   a_in_keep,
    input  logic                         a_in_last,
    input  logic                         a_in_valid,
    output logic                         a_in_ready,
    output logic [3:0][17:0]             a_out_data,
    output logic [$bits(type_t)-1:0]     a_out_typ,
    output logic [3:0]                   a_out_keep,
    output logic                         a_out_last,
    output logic                         a_out_valid,
    input  logic                         a_out_ready,

    input  logic [2:0][12:0]             b_in_data,
    input  logic                         b_in_valid,
    output logic                         b_in_ready,
    output logic [2:0][12:0]             b_out_data,
    output logic                         b_out_valid,
    input  logic                         b_out_ready
);

typedef logic [17:0] id_t;
typedef struct packed {
    logic [7:0] a;
    logic [4:0] b;
} pair_t;

typed_ndata_i #(4, id_t)   a_in  (.clk(clk), .rst_n(rst_n));
typed_ndata_i #(4, id_t)   a_out (.clk(clk), .rst_n(rst_n));
typed_ndata_i #(3, pair_t) b_in  (.clk(clk), .rst_n(rst_n));
typed_ndata_i #(3, pair_t) b_out (.clk(clk), .rst_n(rst_n));

assign a_in.data   = a_in_data;
assign a_in.typ    = type_t'(a_in_typ);
assign a_in.keep   = a_in_keep;
assign a_in.last   = a_in_last;
assign a_in.valid  = a_in_valid;
assign a_in_ready  = a_in.ready;
assign a_out_data  = a_out.data;
assign a_out_typ   = a_out.typ;
assign a_out_keep  = a_out.keep;
assign a_out_last  = a_out.last;
assign a_out_valid = a_out.valid;
assign a_out.ready = a_out_ready;

assign b_in.data   = b_in_data;
assign b_in.typ    = INT32_T;
assign b_in.keep   = '1;
assign b_in.last   = 1'b0;
assign b_in.valid  = b_in_valid;
assign b_in_ready  = b_in.ready;
assign b_out_data  = b_out.data;
assign b_out_valid = b_out.valid;
assign b_out.ready = b_out_ready;

TypedNDataSkidBuffer #(.DATABEAT_SIZE(4)) inst_a (.clk(clk), .rst_n(rst_n), .in(a_in), .out(a_out));
TypedNDataSkidBuffer #(.DATABEAT_SIZE(3)) inst_b (.clk(clk), .rst_n(rst_n), .in(b_in), .out(b_out));

endmodule
