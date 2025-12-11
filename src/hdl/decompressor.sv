`timescale 1ns / 1ps

`include "libstf_macros.svh"
`include "parcore_types.svh"

import lynxTypes::*;
import libstf::data8_t;

import parcore::page_metadata_t;
import parcore::compression_t;
import parcore::COMPRESSION_SNAPPY;
import parcore::COMPRESSION_RAW;

module Decompressor #(
    parameter NUM_BYTES = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_meta,  // #(page_metadata_t)
    ndata_i.s in,             // #(data8_t, NUM_BYTES)

    ready_valid_i.m out_meta, // #(page_metadata_t)
    ndata_i.m out             // #(data8_t, NUM_BYTES)
);

localparam int MAX_IN_TRANSIT = 8;

`RESET_RESYNC // Reset pipelining

ready_valid_i #(page_metadata_t) meta ();

FIFO #(
    .DEPTH(2),
    .WIDTH($bits(page_metadata_t))
) inst_mask_fifo (
    .i_clk(clk),
    .i_rst_n(reset_synced),

    .i_data(in_meta.data),
    .i_valid(in_meta.valid),
    .i_ready(in_meta.ready),

    .o_data(meta.data),
    .o_valid(meta.valid),
    .o_ready(meta.ready),

    .o_filling_level()
);

typedef enum logic {
    ST_FORWARD,
    ST_DONE
} state_t;
state_t state;

assign out_meta.data = meta.data;
assign out_meta.valid = state == ST_FORWARD && meta.valid;

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        state <= ST_FORWARD;
    end else begin
        case (state)
            ST_FORWARD: begin
                if (meta.valid && out_meta.ready) begin
                    state <= ST_DONE;
                end
            end

            ST_DONE: begin
                if (meta.valid && meta.ready) begin
                    state <= ST_FORWARD;
                end
            end
        endcase
    end
end

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

ready_valid_i #(compression_t) compression_meta ();

// These ready and valid assignments are to make sure that the metadata is
// forwarded before we move to the next state.
assign meta.ready = compression_meta.ready && state == ST_DONE;
assign compression_meta.valid = meta.valid && state == ST_DONE;
assign compression_meta.data = meta.data.compression;

ready_valid_i #(compression_t) metas[1:0] ();

ReadyValidDuplicator #(2) inst_meta_duplicator (
    .clk(clk),
    .rst_n(reset_synced),

    .in(compression_meta),
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
