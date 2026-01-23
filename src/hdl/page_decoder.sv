`timescale 1ns / 1ps

`include "libstf_macros.svh"

import lynxTypes::AXI_DATA_BITS;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

module PageDecoder #(
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    page_decoder_config_i.s conf,
    ndata_i.s in,            // #(data8_t, DATABEAT_SIZE)

    typed_ndata_i.m out      // #(DATABEAT_SIZE)
);

`RESET_RESYNC // Reset pipelining

parameter NUM_IDS = 16;

// ------ Decompressor wiring ---------------------
page_decoder_config_i decompressor_conf ();
ndata_i #(data8_t, DATABEAT_SIZE) decompressor_out ();
Decompressor #(DATABEAT_SIZE) inst_decompressor (
    .clk(clk),
    .rst_n(reset_synced),

    .in_conf(conf),
    .in(in),

    .out_conf(decompressor_conf),
    .out(decompressor_out)
);

// ------ Hybrid decoder wiring -------------------
hybrid_page_decoder_config_i decoder_conf ();
ndata_i #(data8_t, DATABEAT_SIZE) decoder_in ();
ndata_i #(id_t, NUM_IDS) decoder_out ();
HybridPageDecoder #(
    .data_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .NUM_BYTES(DATABEAT_SIZE)
) inst_hybrid_page_decoder (
    .clk(clk),
    .rst_n(reset_synced),

    .conf(decoder_conf),
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
typedef struct packed {
    page_type_t page_type;
    type_t typ;
} state_t;
valid_i #(state_t) state ();

// For debugging purposes
page_type_t state_page_type;
type_t state_typ;
assign state_page_type = state.data.page_type;
assign state_typ = state.data.typ;

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        state.valid <= 0;
        decoder_conf.valid <= 0;
    end else begin
        if (decompressor_conf.ready && decompressor_conf.valid) begin
            state.valid <= 1;
            state.data.page_type <= decompressor_conf.page_type;
            state.data.typ <= decompressor_conf.typ;

            // If the page we're handling now is hybrid, we need to
            // forward the metadata to the HybridDecoder
            decoder_conf.valid = decompressor_conf.page_type == PAGE_TYPE_HYBRID;
            decoder_conf.num_values <= decompressor_conf.num_values;
        end

        if (state.valid) begin
            case (state.data.page_type)
                PAGE_TYPE_HYBRID: begin
                    if (decoder_conf.valid && decoder_conf.ready) begin
                        decoder_conf.valid <= 0;
                    end

                    if (out.valid && out.ready && out.last) begin
                        state.valid <= 0;
                    end
                end

                PAGE_TYPE_DICT: begin
                    if (typed_dictionary_values.valid && typed_dictionary_values.ready && typed_dictionary_values.last) begin
                        state.valid <= 0;
                    end
                end
            endcase
        end
    end
end

assign decompressor_conf.ready = ~state.valid && ~decoder_conf.valid;

// NOTE: meta.ready signifies "ready to receive more input" (not paused) for the
// parent component, it's not meant as a handshaking signal along with valid.
// Valid signifies that the meta signal is valid and its data can be read.
assign decompressor_out.ready = state.valid && (
    (state.data.page_type == PAGE_TYPE_HYBRID && decoder_in.ready)
 || (state.data.page_type == PAGE_TYPE_DICT && typed_dictionary_values.ready)
);

// ------ Driving typed dictionary ----------------
assign typed_dictionary_values.valid = state.valid && state.data.page_type == PAGE_TYPE_DICT && decompressor_out.valid;
assign typed_dictionary_values.typ = state.data.typ;
assign typed_dictionary_values.data = decompressor_out.data;
assign typed_dictionary_values.keep = decompressor_out.keep;
assign typed_dictionary_values.last = decompressor_out.last;

// ------ Driving Hybrid decoder ------------------
assign decoder_in.valid = state.valid && state.data.page_type == PAGE_TYPE_HYBRID && decompressor_out.valid;
assign decoder_in.data = decompressor_out.data;
assign decoder_in.keep = decompressor_out.keep;
assign decoder_in.last = decompressor_out.last;

`ifdef SYNTHESIS
ila_page_decoder inst_ila_page_decoder (
    .clk(clk),
    .probe0(reset_resync),

    .probe1(conf.ready),
    .probe2(conf.valid),

    .probe3(in.ready),
    .probe4(in.valid),
    .probe5(in.last),

    .probe6(out.ready),
    .probe7(out.valid),
    .probe8(out.last),

    .probe9(typed_dictionary_values.ready),
    .probe10(typed_dictionary_values.valid),
    .probe11(typed_dictionary_values.last),

    .probe12(typed_dictionary_ids.ready),
    .probe13(typed_dictionary_ids.valid),
    .probe14(typed_dictionary_ids.last)
);
`endif

endmodule
