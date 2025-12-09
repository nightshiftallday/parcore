`timescale 1ns / 1ps

`include "libstf_macros.svh"
`include "parcore_types.svh"

import lynxTypes::AXI_DATA_BITS;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

module PageDecoder #(
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_meta, // #(page_metadata_t)
    ndata_i.s in,            // #(data8_t, DATABEAT_SIZE)

    typed_ndata_i.m out      // #(DATABEAT_SIZE)
);

`RESET_RESYNC // Reset pipelining

parameter NUM_IDS = 16;

// ------ Decompressor wiring ---------------------
ready_valid_i #(page_metadata_t) decompressor_meta_inner (), decompressor_meta ();
ndata_i #(data8_t, DATABEAT_SIZE) decompressor_out ();
Decompressor #(DATABEAT_SIZE) inst_decompressor (
    .clk(clk),
    .rst_n(reset_synced),

    .in_meta(in_meta),
    .in(in),

    .out_meta(decompressor_meta_inner),
    .out(decompressor_out)
);

SkidBuffer #(page_metadata_t) inst_skid_buffer_meta (
    .clk(clk),
    .rst_n(reset_synced),

    .in(decompressor_meta_inner),
    .out(decompressor_meta)
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
    .rst_n(reset_synced),

    .in_meta(decoder_meta),
    .in(decoder_in),

    .out(decoder_out)
);

ndata_i #(id_t, NUM_IDS) typed_dictionary_ids ();
NDataSkidBuffer #(id_t, NUM_IDS) inst_skid_buffer_decoder (
    .clk(clk),
    .rst_n(reset_synced),

    .in(decoder_out),
    .out(typed_dictionary_ids)
);

// ------ Typed dictionary wiring -----------------
typed_ndata_i #(DATABEAT_SIZE) typed_dictionary_values ();
TypedDictionary #(
    .id_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_typed_dictionary (
    .clk(clk),
    .rst_n(reset_synced),

    .in_values(typed_dictionary_values),
    .in_ids(typed_dictionary_ids),

    .out(out)
);

// ------------------------------------------------
// ------ Design wiring ---------------------------
// ------------------------------------------------

// ------ Preserve+forward metadata ---------------
type_t typ;
valid_i #(page_type_t) meta ();

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        meta.valid <= 0;
        decoder_meta.valid <= 0;
    end else begin
        if (decompressor_meta.ready && decompressor_meta.valid) begin
            meta.valid <= 1;
            meta.data <= decompressor_meta.data.page_type;
            typ <= decompressor_meta.data.typ;

            // If the page we're handling now is hybrid, we need to
            // forward the metadata to the HybridDecoder
            decoder_meta.valid = decompressor_meta.data.page_type == PAGE_TYPE_HYBRID;
            decoder_meta.data <= decompressor_meta.data;
        end

        if (meta.valid) begin
            case (meta.data)
                PAGE_TYPE_HYBRID: begin
                    if (decoder_meta.valid && decoder_meta.ready) begin
                        decoder_meta.valid <= 0;
                    end

                    if (out.valid && out.ready && out.last) begin
                        meta.valid <= 0;
                    end
                end

                PAGE_TYPE_DICT: begin
                    if (typed_dictionary_values.valid && typed_dictionary_values.ready && typed_dictionary_values.last) begin
                        meta.valid <= 0;
                    end
                end
            endcase
        end
    end
end

assign decompressor_meta.ready = ~meta.valid && ~decoder_meta.valid;

// NOTE: meta.ready signifies "ready to receive more input" (not paused) for the
// parent component, it's not meant as a handshaking signal along with valid.
// Valid signifies that the meta signal is valid and its data can be read.
assign decompressor_out.ready = meta.valid && (
    (meta.data == PAGE_TYPE_HYBRID && decoder_in.ready)
 || (meta.data == PAGE_TYPE_DICT && typed_dictionary_values.ready)
);

// ------ Driving typed dictionary ----------------
assign typed_dictionary_values.valid = meta.valid && meta.data == PAGE_TYPE_DICT && decompressor_out.valid;
assign typed_dictionary_values.typ = typ;
assign typed_dictionary_values.data = decompressor_out.data;
assign typed_dictionary_values.keep = decompressor_out.keep;
assign typed_dictionary_values.last = decompressor_out.last;

// ------ Driving Hybrid decoder ------------------
assign decoder_in.valid = meta.valid && meta.data == PAGE_TYPE_HYBRID && decompressor_out.valid;
assign decoder_in.data = decompressor_out.data;
assign decoder_in.keep = decompressor_out.keep;
assign decoder_in.last = decompressor_out.last;

endmodule
