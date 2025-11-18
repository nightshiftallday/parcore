`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "parcore_types.svh"

import lynxTypes::AXI_DATA_BITS;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

// We want to have 1MiB dictionaries. That would take 20 bits to index fully.
// Since the TypedDictionary uses 32bit elements (4 bytes), we take 2 bits of (log2(4)).
typedef logic [17:0] id_t;

module PageDecoder #(
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_meta, // #(page_metadata_t)
    ndata_i.s in,            // #(data8_t, DATABEAT_SIZE)

    typed_ndata_i.m out      // #(DATABEAT_SIZE)
);

parameter NUM_IDS = 16;

// ------ Decompressor wiring ---------------------
ready_valid_i #(page_metadata_t) decompressor_meta ();
ndata_i #(data8_t, DATABEAT_SIZE) decompressor_out ();

Decompressor #(DATABEAT_SIZE) inst_decompressor (
    .clk(clk),
    .rst_n(rst_n),

    .in_meta(in_meta),
    .in(in),

    .out_meta(decompressor_meta),
    .out(decompressor_out)
);

// ------ Hybrid decoder wiring -------------------
ready_valid_i #(page_metadata_t) decoder_meta ();
ndata_i #(data8_t, DATABEAT_SIZE) decoder_in ();
ndata_i #(id_t, NUM_IDS) decoder_out ();

HybridPageDecoder #(
    .data_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .NUM_BYTES(DATABEAT_SIZE)
) inst_hybrid_page_decoder (
    .clk(clk),
    .rst_n(rst_n),

    .in_meta(decoder_meta),
    .in(decoder_in),

    .out(decoder_out)
);

// ------ Typed dictionary wiring -----------------
typed_ndata_i #(DATABEAT_SIZE) typed_dictionary_values ();

TypedDictionary #(
    .id_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_typed_dictionary (
    .clk(clk),
    .rst_n(rst_n),

    .in_values(typed_dictionary_values),
    .in_ids(decoder_out),

    .out(out)
);

// ------------------------------------------------
// ------ Design wiring ---------------------------
// ------------------------------------------------

// ------ Preserve+forward metadata ---------------
hold_data_i #(page_metadata_t) meta ();
ready_valid_i #(page_metadata_t) out_meta ();
logic drop;
HoldForward #(page_metadata_t) inst_hold_meta_transaction (
    .clk(clk),
    .rst_n(rst_n),

    .in_data(decompressor_meta),
    .out_data(out_meta),
    // We want to pause the current input taking when we receive the last databeat
    .pause(decompressor_out.valid && decompressor_out.ready && decompressor_out.last),
    // We want to drop the current metadata when we send the last databeat
    .drop(drop),

    .data(meta)
);

always_comb begin
    if (meta.valid) begin
        case (meta.data.page_type)
            PAGE_TYPE_HYBRID: begin
                drop = out.valid && out.ready && out.last;

                out_meta.ready = decoder_meta.ready;
                decoder_meta.valid = out_meta.valid;
                decoder_meta.data = out_meta.data;
            end

            PAGE_TYPE_DICT: begin
                drop = typed_dictionary_values.valid && typed_dictionary_values.ready && typed_dictionary_values.last;

                // Discard the output metadata, the typed dictinary doesn't need it.
                out_meta.ready = 1;
            end
        endcase
    end else begin
        drop = 0;
    end
end

// NOTE: meta.ready signifies "ready to receive more input" (not paused) for the
// parent component, it's not meant as a handshaking signal along with valid.
// Valid signifies that the meta signal is valid and its data can be read.
assign decompressor_out.ready = meta.ready && meta.valid && (
    (meta.data.page_type == PAGE_TYPE_HYBRID && decoder_in.ready)
 || (meta.data.page_type == PAGE_TYPE_DICT && typed_dictionary_values.ready)
);

// ------ Driving typed dictionary ----------------
assign typed_dictionary_values.valid = meta.ready && meta.valid && meta.data.page_type == PAGE_TYPE_DICT && decompressor_out.valid;
assign typed_dictionary_values.typ = meta.data.typ;
assign typed_dictionary_values.data = decompressor_out.data;
assign typed_dictionary_values.keep = decompressor_out.keep;
assign typed_dictionary_values.last = decompressor_out.last;

// ------ Driving Hybrid decoder ------------------
assign decoder_in.valid = meta.ready && meta.valid && meta.data.page_type == PAGE_TYPE_HYBRID && decompressor_out.valid;
assign decoder_in.data = decompressor_out.data;
assign decoder_in.keep = decompressor_out.keep;
assign decoder_in.last = decompressor_out.last;

endmodule
