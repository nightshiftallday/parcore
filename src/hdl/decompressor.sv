`timescale 1ns / 1ps

`include "libstf_macros.svh"

import lynxTypes::*;
import libstf::data8_t;

import parcore::compression_t;
import parcore::COMPRESSION_SNAPPY;
import parcore::COMPRESSION_RAW;

module Decompressor #(
    parameter NUM_BYTES = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s conf,     // #(compression_t)
    ndata_i.s in,             // #(data8_t, NUM_BYTES)

    ndata_i.m out             // #(data8_t, NUM_BYTES)
);

localparam int MAX_IN_TRANSIT = 8;

`RESET_RESYNC // Reset pipelining

ndata_i #(data8_t, NUM_BYTES) ins[1:0] ();
ndata_i #(data8_t, NUM_BYTES) outs[1:0] ();

// ------ Bypass wiring -------------

NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_bypass (
    .clk(clk),
    .rst_n(reset_synced),

    .in(ins[1]),
    .out(outs[1])
);

// ------ Decompressor wiring -------------

ndata_i #(data8_t, NUM_BYTES) decompressor_inner ();
VHSNUnzipWrapper #(NUM_BYTES) inst_vhsnunzip_wrapper (
    .clk(clk),
    .rst_n(reset_synced),

    .in(ins[0]),
    .out(decompressor_inner)
);
NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_vhsnunzip (
    .clk(clk),
    .rst_n(reset_synced),

    .in(decompressor_inner),
    .out(outs[0])
);

// ------ (De)Multiplexing -------------

ready_valid_i #(compression_t) metas[1:0] ();

ReadyValidDuplicator #(2) inst_meta_duplicator (
    .clk(clk),
    .rst_n(reset_synced),

    .in(conf),
    .out(metas)
);

DataDemultiplexer #(2) inst_demultiplexer (
    .clk(clk),
    .rst_n(reset_synced),

    .select(metas[0]),

    .in(in),
    .out(ins)
);

DataMultiplexer #(data8_t, NUM_BYTES, 2) inst_multiplexer (
    .clk(clk),
    .rst_n(reset_synced),

    .select(metas[1]),

    .in(outs),
    .out(out)
);

endmodule
