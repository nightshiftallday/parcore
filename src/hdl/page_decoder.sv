`timescale 1ns / 1ps

`include "libstf_macros.svh"

import lynxTypes::AXI_DATA_BITS;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

module ColumnChunkDecoder #(
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    column_chunk_decoder_config_i.s column_chunk_conf,
    page_decoder_config_i.s         page_conf,

    ndata_i.s       in,      // #(data8_t, DATABEAT_SIZE)
    typed_ndata_i.m out      // #(DATABEAT_SIZE)
);

`RESET_RESYNC // Reset pipelining

localparam NUM_IDS = 16;

// ------ Decompressor wiring ---------------------
ready_valid_i #(compression_t) decompressor_conf ();
ndata_i #(data8_t, DATABEAT_SIZE) decompressor_out ();
Decompressor #(DATABEAT_SIZE) inst_decompressor (
    .clk(clk),
    .rst_n(reset_synced),

    .conf(decompressor_conf),

    .in(in),
    .out(decompressor_out)
);

// ------ Multiplexing declarations ---------------
localparam int NUM_IN = 3;
typedef enum logic [$bits(page_type_t) - 1:0] {
    IN_HYBRID = PAGE_TYPE_HYBRID,
    IN_DICT = PAGE_TYPE_DICT,
    IN_PLAIN = PAGE_TYPE_PLAIN
} in_selector_t;
`ASSERT_ELAB(NUM_IN <= 2**$bits(in_selector_t))

ndata_i #(data8_t, DATABEAT_SIZE) ins[NUM_IN] ();

localparam int NUM_OUT = 2;
typedef enum logic {
  OUT_HYBRID = 0,
  OUT_PLAIN = 1
} out_selector_t;
`ASSERT_ELAB(NUM_OUT <= 2**$bits(out_selector_t))
typed_ndata_i #(DATABEAT_SIZE) outs[NUM_OUT] ();

ready_valid_i #(in_selector_t) in_select ();
ready_valid_i #(out_selector_t) out_select ();

// ------ Hybrid decoder + Dictionary wiring ------
ready_valid_i #(data32_t) hybrid_conf ();

ndata_i #(id_t, NUM_IDS) hybrid_out ();
HybridPageDecoder #(
    .data_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .NUM_BYTES(DATABEAT_SIZE)
) inst_hybrid (
    .clk(clk),
    .rst_n(reset_synced),

    .conf(hybrid_conf),
    .in(ins[IN_HYBRID]),

    .out(hybrid_out)
);

ndata_i #(id_t, NUM_IDS) dict_ids ();
ready_valid_i #(data32_t) hybrid_num_values ();
NormalizeUntil #(id_t, data32_t, NUM_IDS) inst_normalize_until_hybrid (
    .clk(clk),
    .rst_n(reset_synced),

    .size(hybrid_num_values),

    .in(hybrid_out),
    .out(dict_ids)
);

ready_valid_i #(type_t) dict_type ();
typed_ndata_i #(DATABEAT_SIZE) dict_values ();
NDataToTypedNData #(DATABEAT_SIZE) inst_dict_typed_conversion (
    .clk(clk),
    .rst_n(reset_synced),

    .in_type(dict_type),
    .in(ins[IN_DICT]),

    .out(dict_values)
);

TypedDictionary #(
    .id_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_typed_dictionary (
    .clk(clk),
    .rst_n(reset_synced),

    .in_values(dict_values),
    .in_ids(dict_ids),

    .out(outs[OUT_HYBRID])
);

// ------ Plain wiring ----------------------------
ready_valid_i #(type_t) plain_type ();
typed_ndata_i #(DATABEAT_SIZE) plain_out ();
NDataToTypedNData #(DATABEAT_SIZE) inst_plain_typed_conversion (
    .clk(clk),
    .rst_n(reset_synced),

    .in_type(plain_type),
    .in(ins[IN_PLAIN]),

    .out(plain_out)
);

TypedNDataSkidBuffer #(DATABEAT_SIZE) inst_plain_skid_buffer (
    .clk(clk),
    .rst_n(reset_synced),

    .in(plain_out),
    .out(outs[OUT_PLAIN])
);

// ------ Multiplexing ----------------------------
DataDemultiplexer #(NUM_IN) inst_multiplexer (
    .clk(clk),
    .rst_n(reset_synced),

    .select(in_select),

    .in(decompressor_out),
    .out(ins)
);

typed_ndata_i #(DATABEAT_SIZE) inner_out ();
TypedNDataMultiplexer #(DATABEAT_SIZE, NUM_OUT) inst_demultiplexer (
    .clk(clk),
    .rst_n(reset_synced),

    .select(out_select),

    .in(outs),
    .out(inner_out)
);

// Numebr of values in bytes, so if typ == INT32_T this will be num_values * 4
ready_valid_i #(data64_t) num_values ();
TypedNormalizeUntil #(data64_t, DATABEAT_SIZE) inst_normalize_until_out (
    .clk(clk),
    .rst_n(reset_synced),

    .size(num_values),

    .in(inner_out),
    .out(out)
);

// ------------------------------------------------
// ------ Design wiring ---------------------------
// ------------------------------------------------

// ------ Preserve+forward metadata ---------------
typedef enum logic [1:0] {
    ST_IDLE,
    ST_CONFIGURED,
    ST_PROCESS_PAGE
} state_t;
state_t state;

type_t typ;
logic last_page;

// This is used to track how many values the hybrid pages received so far have
// provided. When this matches the number in hybrid_num_values, then the data
// normalizer should be re-configured for the next series of plain decodings.
data64_t received_hybrid_num_values;
logic has_received_any_hybrid_page;
logic is_last_hybrid_page;

assign is_last_hybrid_page = received_hybrid_num_values == hybrid_num_values.data;

task reset();
    decompressor_conf.valid <= 1'b0;
    num_values.valid <= 1'b0;
    hybrid_num_values.valid <= 1'b0;

    hybrid_conf.valid <= 1'b0;
    dict_type.valid <= 1'b0;
    plain_type.valid <= 1'b0;
    in_select.valid <= 1'b0;
    out_select.valid <= 1'b0;

    typ <= BYTE_T;
    last_page <= 1'b0;
    received_hybrid_num_values <= '0;
    has_received_any_hybrid_page <= 1'b0;
    state <= ST_IDLE;
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        reset();
    end else begin
        case (state)
            ST_IDLE: begin
                if (column_chunk_conf.valid) begin
                    decompressor_conf.data <= column_chunk_conf.compression;

                    num_values.data <= column_chunk_conf.num_values * (GET_TYPE_WIDTH(column_chunk_conf.typ) / 8);
                    num_values.valid <= 1'b1;

                    hybrid_num_values.data <= column_chunk_conf.hybrid_num_values;
                    hybrid_num_values.valid <= 1'b1;

                    typ <= column_chunk_conf.typ;
                    state <= ST_CONFIGURED;
                end
            end

            ST_CONFIGURED: begin
                if (page_conf.valid) begin
                    decompressor_conf.valid <= 1'b1;

                    // In each switch case we:
                    // 1. Route input from the decompressor
                    // 2. Configure the module that will transform/consume the input
                    // 3. Configure the output multiplexing any
                    case (page_conf.page_type)
                        PAGE_TYPE_HYBRID: begin
                            in_select.data <= IN_HYBRID;

                            hybrid_conf.valid <= 1'b1;
                            hybrid_conf.data <= page_conf.num_values;

                            if (~has_received_any_hybrid_page) begin
                                // Only configure the output once for the first
                                // hybrid page.
                                out_select.valid <= 1'b1;
                                out_select.data <= OUT_HYBRID;
                            end

                            has_received_any_hybrid_page <= 1'b1;
                            received_hybrid_num_values <= received_hybrid_num_values + page_conf.num_values;
                        end

                        PAGE_TYPE_DICT: begin
                            in_select.data <= IN_DICT;

                            dict_type.valid <= 1'b1;
                            dict_type.data <= typ;
                        end

                        PAGE_TYPE_PLAIN: begin
                            in_select.data <= IN_PLAIN;

                            plain_type.valid <= 1'b1;
                            plain_type.data <= typ;

                            out_select.valid <= 1'b1;
                            out_select.data <= OUT_PLAIN;
                        end
                    endcase

                    // Input is always consumed, thus always configured
                    in_select.valid <= 1'b1;

                    last_page <= page_conf.last;
                    state <= ST_PROCESS_PAGE;
                end
            end

            ST_PROCESS_PAGE: begin
                if (decompressor_conf.ready) begin
                    decompressor_conf.valid <= 1'b0;
                end

                if (hybrid_conf.ready) begin
                    hybrid_conf.valid <= 1'b0;
                end

                if (dict_type.ready) begin
                    dict_type.valid <= 1'b0;
                end

                if (plain_type.ready) begin
                    plain_type.valid <= 1'b0;
                end

                if (in_select.ready) begin
                    in_select.valid <= 1'b0;
                end

                if (out_select.ready) begin
                    out_select.valid <= 1'b0;
                end

                // If all configurations/selectors are invalid, it means they
                // have been successfully consumed by the multiplexers/decoders
                // (or not been set in the first place) and thus we can move
                // back to either state:
                // - IDLE if this was the last page, thus we're expecting
                //   a new column chunk configuration next.
                // - CONFIGURED if this was not the last page and this column
                //   chunk has more pages to be fully decoded.
                if (~decompressor_conf.valid && ~hybrid_conf.valid && ~dict_type.valid && ~plain_type.valid && ~in_select.valid && (~is_last_hybrid_page || ~out_select.valid)) begin
                    if (last_page) begin
                        reset();
                    end else begin
                        state <= ST_CONFIGURED;
                    end
                end
            end
        endcase

        if (state != ST_IDLE) begin
            if (num_values.ready) begin
                num_values.valid <= 1'b0;
            end

            if (hybrid_num_values.ready) begin
                hybrid_num_values.valid <= 1'b0;
            end
        end
    end
end

assign column_chunk_conf.ready = state == ST_IDLE;
assign page_conf.ready = state == ST_CONFIGURED;

endmodule
