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

valid_i #(page_metadata_t) meta (); // Used for inernal state management
valid_i #(page_metadata_t) forward_meta (); // Used to forward the metadata to the next component

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        meta.valid <= 0;
        forward_meta.valid <= 0;
    end else begin
        if (in_meta.ready && in_meta.valid) begin
            meta.data <= in_meta.data;
            meta.valid <= 1;
            forward_meta.data <= in_meta.data;
            forward_meta.valid <= 1;
        end

        if (out.ready && out.valid && out.last) begin
            meta.valid <= 0;
        end

        if (out_meta.ready && out_meta.valid) begin
            forward_meta.valid <= 0;
        end
    end
end

// ------ Bypass wiring -------------

ndata_i #(data8_t, NUM_BYTES) bypass_in (), bypass_out ();
assign bypass_in.data = in.data;
assign bypass_in.keep = in.keep;
assign bypass_in.last = in.last;
assign bypass_in.valid = meta.valid && meta.data.compression == COMPRESSION_RAW && in.valid;

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
assign decompressor_in.valid = meta.valid && meta.data.compression == COMPRESSION_SNAPPY && in.valid;

// Decompressor input paused and reset logic
reg decompressor_input_paused;
reg [1:0] decompressor_reset_counter;

// Snappy decompressor
VHSNUnzipWrapper #(NUM_BYTES) inst_vhsnunzip_wrapper (
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

assign in_meta.ready = ~meta.valid && ~forward_meta.valid;

assign in.ready = meta.valid && (
    (meta.data.compression == COMPRESSION_SNAPPY && decompressor_in.ready && !decompressor_input_paused)
 || (meta.data.compression == COMPRESSION_RAW && bypass_in.ready)
);

// ------ Wiring output --------------

assign out.valid = meta.valid && (meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.valid : bypass_out.valid);
assign out.data  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.data  : bypass_out.data;
assign out.keep  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.keep  : bypass_out.keep;
assign out.last  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.last  : bypass_out.last;

assign decompressor_out.ready = meta.valid && meta.data.compression == COMPRESSION_SNAPPY && out.ready;
assign bypass_out.ready = meta.valid && meta.data.compression == COMPRESSION_RAW && out.ready;

assign out_meta.data = forward_meta.data;
assign out_meta.valid = forward_meta.valid;

// `ifdef SYNTHESIS
// ila_decompressor inst_ila_decompressor (
//     .clk(clk),
//     .probe0(reset_resync),
//
//     .probe1(meta.ready),
//     .probe2(meta.valid),
//     .probe3(meta.data),
//
//     .probe4(in.ready),
//     .probe5(in.valid),
//     .probe6(in.last),
//
//     .probe7(out.ready),
//     .probe8(out.valid),
//     .probe9(out.last),
//
//     .probe10(out.data[0]),
//     .probe11(out.data[1]),
//     .probe12(out.data[2]),
//     .probe13(out.data[3]),
//
//     .probe14(out.data[NUM_BYTES - 1]),
//     .probe15(out.data[NUM_BYTES - 2]),
//     .probe16(out.data[NUM_BYTES - 3]),
//     .probe17(out.data[NUM_BYTES - 4])
// );
// `endif

endmodule
