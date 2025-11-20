`timescale 1ns / 1ps

`include "libstf_macros.svh"
`include "parcore_types.svh"

import lynxTypes::*;
import libstf::data8_t;

import parcore::page_metadata_t;
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

`RESET_RESYNC // Reset pipelining

hold_data_i #(page_metadata_t) meta ();
HoldForward #(page_metadata_t) inst_hold_meta_transaction (
    .clk(clk),
    .rst_n(reset_synced),

    .in_data(in_meta),
    .out_data(out_meta),
    // We want to pause the current input taking when we receive the last databeat
    .pause(in.valid && in.ready && in.last),
    // We want to drop the current metadata when we send the last databeat
    .drop(out.valid && out.ready && out.last),

    .data(meta)
);

// ------ Bypass wiring -------------

ndata_i #(data8_t, NUM_BYTES) bypass_in (), bypass_out ();
assign bypass_in.data = in.data;
assign bypass_in.keep = in.keep;
assign bypass_in.last = in.last;
assign bypass_in.valid = meta.ready && meta.valid && meta.data.compression == COMPRESSION_RAW && in.valid;

NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_bypass (
    .clk(clk),
    .rst_n(reset_synced),

    .in(bypass_in),
    .out(bypass_out)
);

// ------ Decompressor wiring -------------

ndata_i #(data8_t, NUM_BYTES) decompressor_in (), decompressor_out_inner (), decompressor_out ();
assign decompressor_in.data = in.data;
assign decompressor_in.keep = in.keep;
assign decompressor_in.last = in.last;
assign decompressor_in.valid = meta.ready && meta.valid && meta.data.compression == COMPRESSION_SNAPPY && in.valid;

// Decompressor input paused and reset logic
reg decompressor_input_paused;
reg [1:0] decompressor_reset_counter;

// Snappy decompressor
VHSNunzipWrapper #(NUM_BYTES) inst_vhsnunzip_wrapper (
    .clk(clk),
    .rst_n(reset_synced && decompressor_reset_counter == 3'd0),

    .in(decompressor_in),
    .out(decompressor_out_inner)
);

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        decompressor_input_paused <= 1'b0;
        decompressor_reset_counter <= 0;
    end else begin
        if (decompressor_in.ready && decompressor_in.valid && decompressor_in.last) begin
            decompressor_input_paused <= 1'b1;
        end else if (decompressor_input_paused && decompressor_out_inner.ready && decompressor_out_inner.valid && decompressor_out_inner.last) begin
            decompressor_reset_counter <= 2'd2;
        end else if (decompressor_input_paused && decompressor_reset_counter > 0) begin
            if (decompressor_reset_counter == 2'd1) begin
                decompressor_input_paused <= 1'b0;
            end
            decompressor_reset_counter <= decompressor_reset_counter - 1;
        end
    end
end

NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_vhsnunzip (
    .clk(clk),
    .rst_n(reset_synced),

    .in(decompressor_out_inner),
    .out(decompressor_out)
);

// ------ Readying input --------------

assign in.ready = meta.ready && meta.valid && (
    (meta.data.compression == COMPRESSION_SNAPPY && decompressor_in.ready && !decompressor_input_paused)
 || (meta.data.compression == COMPRESSION_RAW && bypass_in.ready)
);

// ------ Wiring output --------------

assign out.valid = meta.valid && (meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.valid : bypass_out.valid);
assign out.data  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.data  : bypass_out.data;
assign out.keep  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.keep  : bypass_out.keep;
assign out.last  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.last  : bypass_out.last;

assign decompressor_out.ready = meta.data.compression == COMPRESSION_SNAPPY && out.ready;
assign bypass_out.ready = meta.data.compression == COMPRESSION_RAW && out.ready;

endmodule
