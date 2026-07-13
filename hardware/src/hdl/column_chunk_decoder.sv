`timescale 1ns / 1ps

`include "libstf_macros.svh"

import lynxTypes::AXI_DATA_BITS;
import libstf::data8_t;
import libstf::data32_t;
import libstf::type_t;
import libstf::BYTE_T;
import libstf::GERMAN_STR_T;
import libstf::vaddress_t;
import parcore::*;

module ColumnChunkDecoder #(
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s conf, // #(column_chunk_conf_t)

    ndata_i.s       in,       // #(data8_t, DATABEAT_SIZE) raw column-chunk bytes
    typed_ndata_i.m out,      // #(DATABEAT_SIZE) values (INT32_T german records for strings); one `last` per chunk
    ndata_i.m       heap_out, // #(data8_t, DATABEAT_SIZE) packed string heap bytes; one `last` per chunk

    decoder_profile_i.m profile
);

`RESET_RESYNC // Reset pipelining

function automatic int unsigned max(int unsigned a, int unsigned b);
    return (a > b) ? a : b;
endfunction


localparam NUM_IDS = max(8, DATABEAT_SIZE / ($bits(data32_t) / 8));
localparam NUM_STR_IDS = DATABEAT_SIZE / ($bits(german_str_t) / 8);

// ------ Multiplexing declarations ---------------
localparam int NUM_IN = 3;
typedef logic [1:0] in_selector_t;
`ASSERT_ELAB(NUM_IN <= 2**$bits(in_selector_t))

ndata_i #(data8_t, DATABEAT_SIZE) ins[NUM_IN](clk, reset_synced);

localparam int NUM_OUT = 3;
typedef enum logic [1:0] {
  OUT_HYBRID    = 0,
  OUT_PLAIN     = 1,
  OUT_STR_PLAIN = 2
} out_selector_t;
`ASSERT_ELAB(NUM_OUT <= 2**$bits(out_selector_t))
typed_ndata_i #(DATABEAT_SIZE) outs[NUM_OUT](clk, reset_synced);

ready_valid_i #(in_selector_t)  in_select(clk, reset_synced);
ready_valid_i #(out_selector_t) out_select(clk, reset_synced);

ready_valid_i #(logic) hybrid_ids_select(clk, reset_synced);
ready_valid_i #(logic) dict_bytes_select(clk, reset_synced);
ready_valid_i #(logic) plain_bytes_select(clk, reset_synced);
ready_valid_i #(logic) psd_src_select(clk, reset_synced);
ready_valid_i #(logic) g2t_select(clk, reset_synced);
ready_valid_i #(logic) dict_values_select(clk, reset_synced);
ready_valid_i #(logic) dict_ids_select(clk, reset_synced);

// ------ PageHeaderParser wiring -----------------
ready_valid_i #(column_chunk_conf_t) chunk_confs[2](clk, reset_synced);
ready_valid_i #(page_conf_t)         page_conf(clk, reset_synced);

ReadyValidDuplicator #(2) inst_chunk_conf_duplicator (
    .clk(clk),
    .rst_n(reset_synced),

    .in(conf),
    .out(chunk_confs)
);
ndata_i #(data8_t, DATABEAT_SIZE) page_payload(clk, reset_synced);

PageHeaderParser #(
    .NUM_BYTES(DATABEAT_SIZE)
) inst_page_header_parser (
    .clk(clk),
    .rst_n(reset_synced),

    .chunk_conf(chunk_confs[1]),

    .in(in),
    .out(page_payload),

    .page_conf(page_conf)
);

// ------ Decompressor wiring ---------------------
ready_valid_i #(compression_t) decompressor_conf(clk, reset_synced);
ndata_i #(data8_t, DATABEAT_SIZE) decompressor_out(clk, reset_synced);
Decompressor #(DATABEAT_SIZE) inst_decompressor (
    .clk(clk),
    .rst_n(reset_synced),

    .conf(decompressor_conf),

    .in(page_payload),
    .out(decompressor_out)
);

DataDemultiplexer #(NUM_IN) inst_multiplexer (
    .clk(clk),
    .rst_n(reset_synced),

    .select(in_select),

    .in(decompressor_out),
    .out(ins)
);

// ------ Shared dictionary input muxes -----------
typed_ndata_i #(DATABEAT_SIZE) dict_in_values_src[2](clk, reset_synced);
ndata_i #(id_t, NUM_IDS)       dict_in_ids_src[2](clk, reset_synced);

typed_ndata_i #(DATABEAT_SIZE) dict_values(clk, reset_synced);
ndata_i #(id_t, NUM_IDS)       dict_ids(clk, reset_synced);

TypedNDataMultiplexer #(DATABEAT_SIZE, 2) inst_dict_values_mux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(dict_values_select),

    .in(dict_in_values_src),
    .out(dict_values)
);

DataMultiplexer #(
    .data_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .NUM_STREAMS(2)
) inst_dict_ids_mux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(dict_ids_select),

    .in(dict_in_ids_src),
    .out(dict_ids)
);

// ------ Shared hybrid decoder + id expansion -----
data_i #(data32_t) hybrid_conf(clk, reset_synced);
ndata_i #(id_t, NUM_IDS) hybrid_ids(clk, reset_synced);

HybridPageDecoder #(
    .data_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .NUM_BYTES(DATABEAT_SIZE)
) inst_hybrid_page_decoder (
    .clk(clk),
    .rst_n(reset_synced),

    .conf(hybrid_conf),
    .in(ins[PAGE_TYPE_HYBRID]),

    .out(hybrid_ids)
);

// Fixed-width ids go to the dictionary directly; string (german) ids are
// narrowed to NUM_STR_IDS/beat and expanded x4 into int32-slot ids.
ndata_i #(id_t, NUM_IDS) hybrid_split[2](clk, reset_synced);
DataDemultiplexer #(2) inst_hybrid_ids_demux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(hybrid_ids_select),

    .in(hybrid_ids),
    .out(hybrid_split)
);
`DATA_ASSIGN(hybrid_split[0], dict_in_ids_src[0])

ndata_i #(id_t, NUM_STR_IDS) german_ids(clk, reset_synced);
NDataWidthConverter #(
    .data_t(id_t)
) inst_str_ids_narrow (
    .clk(clk),
    .rst_n(reset_synced),

    .in(hybrid_split[1]),
    .out(german_ids)
);

IndexExpander #(
    .id_t(id_t),
    .NUM_ELEMENTS_IN(NUM_STR_IDS),
    .IN_WIDTH($bits(german_str_t)), // 128b german string
    .OUT_WIDTH(32)                  // raw int32 dictionary slot
) inst_str_index_expander (
    .clk(clk),
    .rst_n(reset_synced),

    .in(german_ids),
    .out(dict_in_ids_src[1])
);

// ------ Shared dictionary + per-page last rewrite -
typed_ndata_i #(DATABEAT_SIZE) hybrid_typed(clk, reset_synced);
TypedDictionary #(
    .id_t(id_t),
    .NUM_ELEMENTS(NUM_IDS),
    .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_typed_dictionary (
    .clk(clk),
    .rst_n(reset_synced),

    .in_values(dict_values),
    .in_ids(dict_ids),

    .out(hybrid_typed)
);

// The TypedDictionary emits a single `last` per read group, but the output
// multiplexer consumes out_select per page. This re-injects a per-page `last`
// after each page's worth of values.
ready_valid_i #(data32_t) hybrid_num_values(clk, reset_synced);
TypedRewriteLast #(
    .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_hybrid_set_last (
    .clk(clk),
    .rst_n(reset_synced),

    .num_elements(hybrid_num_values),

    .in(hybrid_typed),
    .out(outs[OUT_HYBRID])
);

// ------ DICT page byte routing ------------------
ready_valid_i #(type_t) dict_type(clk, reset_synced);

ndata_i #(data8_t, DATABEAT_SIZE) dict_split[2](clk, reset_synced);
DataDemultiplexer #(2) inst_dict_bytes_demux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(dict_bytes_select),

    .in(ins[PAGE_TYPE_DICT]),
    .out(dict_split)
);

NDataToTypedNData #(DATABEAT_SIZE) inst_dict_typed_conversion (
    .clk(clk),
    .rst_n(reset_synced),

    .in_type(dict_type),
    .in(dict_split[0]),

    .out(dict_in_values_src[0])
);

// ------ PLAIN page byte routing -----------------
ready_valid_i #(type_t) plain_type(clk, reset_synced);
ndata_i #(data8_t, DATABEAT_SIZE) plain_in(clk, reset_synced);
ndata_i #(data8_t, DATABEAT_SIZE) plain_stripped(clk, reset_synced), plain_out(clk, reset_synced);

NDataSkidBuffer #(data8_t, DATABEAT_SIZE) inst_plain_in_skid_buffer (
    .clk(clk),
    .rst_n(reset_synced),

    .in(ins[PAGE_TYPE_PLAIN]),
    .out(plain_in)
);

StripLevels #(
    .NUM_BYTES(DATABEAT_SIZE)
) inst_strip_levels (
    .clk(clk),
    .rst_n(reset_synced),

    .in(plain_in),
    .out(plain_stripped)
);

NDataSkidBuffer #(data8_t, DATABEAT_SIZE) inst_plain_stripped_skid_buffer  (
    .clk(clk),
    .rst_n(reset_synced),

    .in(plain_stripped),
    .out(plain_out)
);

ndata_i #(data8_t, DATABEAT_SIZE) plain_split[2](clk, reset_synced);
DataDemultiplexer #(2) inst_plain_bytes_demux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(plain_bytes_select),

    .in(plain_out),
    .out(plain_split)
);

NDataToTypedNData #(DATABEAT_SIZE) inst_plain_type (
    .clk(clk),
    .rst_n(reset_synced),

    .in_type(plain_type),
    .in(plain_split[0]),

    .out(outs[OUT_PLAIN])
);

// ------ Shared string decode chain ---------------
// DICT and PLAIN string pages share one PlainStringDecoder -> G2T chain: the
// decoder parses plain-encoded strings straight into german records and
// forwards the raw page bytes as heap. The records of a DICT page load the
// dictionary; the records of a PLAIN page go straight to the value output.
ndata_i #(data8_t, DATABEAT_SIZE) psd_src[2](clk, reset_synced);
`DATA_ASSIGN(dict_split[1],  psd_src[0])
`DATA_ASSIGN(plain_split[1], psd_src[1])

ndata_i #(data8_t, DATABEAT_SIZE) psd_in(clk, reset_synced);
DataMultiplexer #(
    .data_t(data8_t),
    .NUM_ELEMENTS(DATABEAT_SIZE),
    .NUM_STREAMS(2)
) inst_psd_src_mux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(psd_src_select),

    .in(psd_src),
    .out(psd_in)
);

ready_valid_i #(str_decoder_conf_t)        psd_conf(clk, reset_synced);
data_i #(german_str_t)                     german_strings_unskidded(clk, reset_synced);
data_i #(german_str_t)                     german_strings(clk, reset_synced);
ndata_i #(data8_t, DATABEAT_SIZE)          heap_raw(clk, reset_synced);

// Latched per page by the FSM; combined with the live heap offset into
// psd_conf.data in the heap-output section below.
data32_t psd_num_values;

PlainStringDecoder #(
    .STREAM_WIDTH(DATABEAT_SIZE)
) inst_psd (
    .clk(clk),
    .rst_n(reset_synced),

    .conf(psd_conf),
    .in_data(psd_in),
    .out_strings(german_strings_unskidded),
    .out_data(heap_raw)
);

// Register slice between the decoder's string assembly (a wide byte mux over
// its lookahead view) and the G2T packer.
DataSkidBuffer #(
    .data_t(german_str_t)
) inst_psd_strings_skid (
    .clk(clk),
    .rst_n(reset_synced),

    .in(german_strings_unskidded),
    .out(german_strings)
);

typed_ndata_i #(DATABEAT_SIZE) g2t_typed(clk, reset_synced);
GermanStrToTypedNData #(
    .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_g2t (
    .clk(clk),
    .rst_n(reset_synced),

    .in(german_strings),
    .out(g2t_typed)
);

typed_ndata_i #(DATABEAT_SIZE) g2t_split[2](clk, reset_synced);
TypedNDataDemultiplexer #(DATABEAT_SIZE, 2) inst_g2t_demux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(g2t_select),

    .in(g2t_typed),
    .out(g2t_split)
);

assign dict_in_values_src[1].data  = g2t_split[0].data;
assign dict_in_values_src[1].typ   = g2t_split[0].typ;
assign dict_in_values_src[1].keep  = g2t_split[0].keep;
assign dict_in_values_src[1].last  = g2t_split[0].last;
assign dict_in_values_src[1].valid = g2t_split[0].valid;
assign g2t_split[0].ready = dict_in_values_src[1].ready;

assign outs[OUT_STR_PLAIN].data  = g2t_split[1].data;
assign outs[OUT_STR_PLAIN].typ   = g2t_split[1].typ;
assign outs[OUT_STR_PLAIN].keep  = g2t_split[1].keep;
assign outs[OUT_STR_PLAIN].last  = g2t_split[1].last;
assign outs[OUT_STR_PLAIN].valid = g2t_split[1].valid;
assign g2t_split[1].ready = outs[OUT_STR_PLAIN].ready;

// ------ Value output -------------------------------------
// Per-page sub-streams are muxed and re-packed into one dense stream whose
// `last` falls after the chunk's total value count.
typed_ndata_i #(DATABEAT_SIZE) inner_out(clk, reset_synced);
TypedNDataMultiplexer #(DATABEAT_SIZE, NUM_OUT) inst_out_mux (
    .clk(clk),
    .rst_n(reset_synced),

    .select(out_select),

    .in(outs),
    .out(inner_out)
);

ready_valid_i #(data32_t) num_values(clk, reset_synced);
TypedNormalizeUntil #(
    .size_t(data32_t),
    .DATABEAT_SIZE(DATABEAT_SIZE),
    .BARREL_SHIFTER_REGISTER_LEVELS(2)
) inst_normalize_until_out (
    .clk(clk),
    .rst_n(reset_synced),

    .size(num_values),

    .in(inner_out),
    .out(out)
);

// ------ Heap output --------------------------------------
vaddress_t heap_offset;

assign psd_conf.data.num_values = psd_num_values;
assign psd_conf.data.heap_addr  = heap_offset;

// A string chunk ending on a HYBRID page produces no heap on its final page,
// so the heap normalizer would never see the chunk-final flush that releases
// the dictionary page's carried heap residue. The FSM then injects a synthetic
// empty final heap beat once every configured heap page has drained.
logic heap_dummy_pending, heap_dummy_now;
logic [15:0] heap_pages_cfgd, heap_lasts_seen;

ndata_i #(data8_t, DATABEAT_SIZE) heap_in(clk, reset_synced);

assign heap_in.data   = heap_raw.data;
assign heap_in.keep   = heap_raw.valid ? heap_raw.keep : '0;
assign heap_in.last   = heap_raw.valid ? heap_raw.last : 1'b1;
assign heap_in.valid  = heap_raw.valid || heap_dummy_now;
assign heap_raw.ready = heap_in.ready;

// Register slice: cuts the timing path from the decoder's beat-emission
// decode (handshake cloud) into the normalizer logic. All
// heap bookkeeping (offset accumulator, dummy machinery) observes heap_in,
// upstream of the slice, so its accounting is unaffected by the extra beat
// of buffering.
ndata_i #(data8_t, DATABEAT_SIZE) heap_in_buf(clk, reset_synced);

NDataSkidBuffer #(data8_t, DATABEAT_SIZE) inst_heap_in_skid_buffer (
    .clk(clk),
    .rst_n(reset_synced),

    .in(heap_in),
    .out(heap_in_buf)
);

// One flag per heap-producing page: 1 = this page ends the chunk's heap.
// Non-final page lasts are merged across so the heap lands contiguously in
// its buffer; the chunk-final page (or the synthetic dummy) flushes.
ready_valid_i #(logic) page_last_cross_page_normalizer(clk, reset_synced);

CrossPageNormalizer #(
    .NUM_BYTES(DATABEAT_SIZE)
) inst_heap_normalizer (
    .clk(clk),
    .rst_n(reset_synced),

    .page_last(page_last_cross_page_normalizer),

    .in(heap_in_buf),
    .out(heap_out)
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
logic  is_string;
assign is_string = (typ == GERMAN_STR_T);
logic last_page;

// Whether this chunk has had a dictionary page (and thus whether the dictionary path
// needs a dummy last ids beat) for the TypedDictionary to reset its internal state.
logic dict_seen;

// Whether a dictionary ids read group is open: HYBRID pages share one read
// group spanning all of the chunk's HYBRID pages (ids `last` only on the
// chunk-final one), so the stored dictionary survives from page to page. The
// id-path selects are pushed once per group — a per-page push would leave a
// stale select latched in the demux/mux at every group boundary. A chunk that
// ends on a non-HYBRID page closes the group with the dummy ids beat.
logic ids_group_open;

// ------ Heap offset accumulator -----------------
// Advances heap_offset by the accepted heap bytes on every beat, so the next
// heap-producing page bakes pointers at the right absolute address. Per-beat
// accumulation (rather than latching per page) keeps the adder a single
// short-operand add: the decoder samples heap_offset only in WAIT_CONF, one or
// more cycles after it emitted the previous page's final beat into heap_in,
// where the running per-beat sum equals the page-boundary value.
logic [$clog2(DATABEAT_SIZE):0] heap_beat_bytes;
assign heap_beat_bytes = $countones(heap_in.keep);

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        heap_offset <= '0;
    end else if (state == ST_IDLE && chunk_confs[0].valid && chunk_confs[0].ready) begin
        heap_offset <= chunk_confs[0].data.heap_base_addr;
    end else if (heap_in.valid && heap_in.ready) begin
        heap_offset <= heap_offset + vaddress_t'(heap_beat_bytes);
    end
end

// ------ Heap dummy-beat injection ---------------
// Fires only once all configured heap pages have drained (the dummy's own
// flag is the one unmatched entry) and the decoder is quiet.
assign heap_dummy_now = heap_dummy_pending && !page_last_cross_page_normalizer.valid && !heap_raw.valid
                     && (heap_lasts_seen == heap_pages_cfgd - 16'd1);

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        heap_pages_cfgd <= '0;
        heap_lasts_seen <= '0;
    end else if (state == ST_IDLE && chunk_confs[0].valid && chunk_confs[0].ready) begin
        heap_pages_cfgd <= '0;
        heap_lasts_seen <= '0;
    end else begin
        if (page_last_cross_page_normalizer.valid && page_last_cross_page_normalizer.ready) begin
            heap_pages_cfgd <= heap_pages_cfgd + 16'd1;
        end
        if (heap_in.valid && heap_in.ready && heap_in.last && !heap_dummy_now) begin
            heap_lasts_seen <= heap_lasts_seen + 16'd1;
        end
    end
end

// A string store page (DICT or PLAIN) must not be configured while the
// previous store stream still owns the shared PSD/G2T/dictionary-store
// selects: mux selects are consumed only at stream `last`, so an early
// overwrite would lose one and deadlock the second stream.
logic store_busy, page_accept;
assign store_busy  = psd_src_select.valid || dict_values_select.valid || g2t_select.valid;
assign page_accept = page_conf.valid && page_conf.ready;

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        decompressor_conf.valid <= 1'b0;
        num_values.valid        <= 1'b0;
        hybrid_num_values.valid <= 1'b0;

        hybrid_conf.valid       <= 1'b0;
        dict_type.valid         <= 1'b0;
        plain_type.valid        <= 1'b0;
        in_select.valid         <= 1'b0;
        out_select.valid        <= 1'b0;

        psd_conf.valid          <= 1'b0;

        hybrid_ids_select.valid <= 1'b0;
        dict_bytes_select.valid <= 1'b0;
        plain_bytes_select.valid<= 1'b0;
        psd_src_select.valid    <= 1'b0;
        g2t_select.valid        <= 1'b0;
        dict_values_select.valid<= 1'b0;
        dict_ids_select.valid   <= 1'b0;

        page_last_cross_page_normalizer.valid        <= 1'b0;
        heap_dummy_pending      <= 1'b0;

        typ          <= BYTE_T;
        last_page    <= 'X;
        dict_seen    <= 1'b0;
        ids_group_open <= 1'b0;
        state        <= ST_IDLE;
    end else begin
        case (state)
            ST_IDLE: begin
                if (chunk_confs[0].valid && chunk_confs[0].ready) begin
                    decompressor_conf.data <= chunk_confs[0].data.compression;

                    // German strings are emitted as four raw int32 slots, so
                    // the output normalizer counts 4x as many values.
                    num_values.data  <= (chunk_confs[0].data.typ == GERMAN_STR_T) ?
                                        (chunk_confs[0].data.num_values << 2) :
                                        chunk_confs[0].data.num_values;
                    num_values.valid <= 1'b1;

                    typ            <= chunk_confs[0].data.typ;
                    dict_seen      <= 1'b0;
                    ids_group_open <= 1'b0;
                    state          <= ST_CONFIGURED;
                end
            end
            ST_CONFIGURED: begin
                if (page_accept) begin
                    // Input is always consumed, thus always configured
                    in_select.data  <= in_selector_t'(page_conf.data.page_type);
                    in_select.valid <= 1'b1;

                    last_page <= page_conf.data.last;
                    state     <= ST_PROCESS_PAGE;

                    decompressor_conf.valid <= 1'b1;

                    // In each switch case we:
                    // 1. Route input from the decompressor
                    // 2. Configure the module that will transform/consume the input
                    // 3. Configure the output multiplexing if any
                    case (page_conf.data.page_type)
                        PAGE_TYPE_HYBRID: begin
                            hybrid_conf.data  <= page_conf.data.num_values;
                            hybrid_conf.keep  <= 1'b1;
                            hybrid_conf.last  <= page_conf.data.last;
                            hybrid_conf.valid <= 1'b1;

                            // The id-path selects are held for the whole read
                            // group; only its first page pushes them.
                            if (!ids_group_open) begin
                                hybrid_ids_select.data  <= is_string;
                                hybrid_ids_select.valid <= 1'b1;

                                dict_ids_select.data  <= is_string;
                                dict_ids_select.valid <= 1'b1;
                            end
                            ids_group_open <= !page_conf.data.last;

                            if (!is_string) begin
                                hybrid_num_values.data <= page_conf.data.num_values;
                            end else begin
                                // Four int32 dictionary slots per german string.
                                hybrid_num_values.data <= page_conf.data.num_values << 2;

                                // A string chunk ending on a hybrid page emits
                                // no more heap: flush the heap normalizer's
                                // residue with a synthetic final heap page.
                                if (page_conf.data.last) begin
                                    page_last_cross_page_normalizer.data    <= 1'b1;
                                    page_last_cross_page_normalizer.valid   <= 1'b1;
                                    heap_dummy_pending <= 1'b1;
                                end
                            end
                            hybrid_num_values.valid <= 1'b1;

                            out_select.data  <= OUT_HYBRID;
                            out_select.valid <= 1'b1;
                        end
                        PAGE_TYPE_DICT: begin
                            dict_bytes_select.data  <= is_string;
                            dict_bytes_select.valid <= 1'b1;

                            if (!is_string) begin
                                dict_type.data  <= typ;
                                dict_type.valid <= 1'b1;

                                dict_values_select.data  <= 1'b0;
                                dict_values_select.valid <= 1'b1;
                            end else begin
                                psd_num_values <= page_conf.data.num_values;
                                psd_conf.valid <= 1'b1;

                                psd_src_select.data  <= 1'b0;
                                psd_src_select.valid <= 1'b1;

                                g2t_select.data  <= 1'b0;
                                g2t_select.valid <= 1'b1;

                                dict_values_select.data  <= 1'b1;
                                dict_values_select.valid <= 1'b1;

                                page_last_cross_page_normalizer.data  <= page_conf.data.last;
                                page_last_cross_page_normalizer.valid <= 1'b1;
                            end

                            dict_seen <= 1'b1;
                        end
                        PAGE_TYPE_PLAIN: begin
                            plain_bytes_select.data  <= is_string;
                            plain_bytes_select.valid <= 1'b1;

                            if (!is_string) begin
                                plain_type.data  <= typ;
                                plain_type.valid <= 1'b1;

                                out_select.data  <= OUT_PLAIN;
                                out_select.valid <= 1'b1;
                            end else begin
                                psd_num_values <= page_conf.data.num_values;
                                psd_conf.valid <= 1'b1;

                                psd_src_select.data  <= 1'b1;
                                psd_src_select.valid <= 1'b1;

                                g2t_select.data  <= 1'b1;
                                g2t_select.valid <= 1'b1;

                                out_select.data  <= OUT_STR_PLAIN;
                                out_select.valid <= 1'b1;

                                page_last_cross_page_normalizer.data  <= page_conf.data.last;
                                page_last_cross_page_normalizer.valid <= 1'b1;
                            end

                            if (page_conf.data.last && dict_seen) begin
                                // The chunk ends on a non-hybrid page but there
                                // was a dictionary page. Inject a dummy ids
                                // beat (keep=0, last=1) so the TypedDictionary
                                // closes its read group and clears its state.
                                hybrid_conf.data  <= '0;
                                hybrid_conf.keep  <= 1'b0;
                                hybrid_conf.last  <= 1'b1;
                                hybrid_conf.valid <= 1'b1;

                                // With an open read group the id-path selects
                                // are still latched; the dummy beat travels
                                // under them and releases them. Otherwise
                                // route it freshly.
                                if (!ids_group_open) begin
                                    hybrid_ids_select.data  <= is_string;
                                    hybrid_ids_select.valid <= 1'b1;

                                    dict_ids_select.data  <= is_string;
                                    dict_ids_select.valid <= 1'b1;
                                end
                                ids_group_open <= 1'b0;
                            end
                        end
                    endcase
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

                if (psd_conf.ready) begin
                    psd_conf.valid <= 1'b0;
                end

                if (in_select.ready) begin
                    in_select.valid <= 1'b0;
                end

                if (out_select.ready) begin
                    out_select.valid <= 1'b0;
                end

                if (hybrid_num_values.ready) begin
                    hybrid_num_values.valid <= 1'b0;
                end

                // If all configurations/selectors are invalid, it means they
                // have been successfully consumed by the multiplexers/decoders
                // (or not been set in the first place) and thus we can move
                // back to either state:
                // - IDLE if this was the last page, thus we're expecting
                //   a new column chunk configuration next.
                // - CONFIGURED if this was not the last page and this column
                //   chunk has more pages to be fully decoded.
                if (!decompressor_conf.valid && !hybrid_conf.valid && !dict_type.valid && !plain_type.valid
                    && !psd_conf.valid && !page_last_cross_page_normalizer.valid
                    && !in_select.valid && !out_select.valid) begin
                    if (last_page) begin
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_CONFIGURED;
                    end
                end
            end
        endcase

        // These selectors and flag pushes are consumed by their muxes/FIFOs on
        // the muxed stream's `last` (or FIFO acceptance), independently of the
        // page FSM, so clear them whenever the consumer accepts them rather
        // than gating the page transition. The clears are qualified with the
        // pre-edge `valid`: demultiplexer selects and flag FIFOs hold `ready`
        // high while idle, and an unqualified clear would cancel a same-edge
        // set (last assignment wins).
        if (hybrid_ids_select.valid && hybrid_ids_select.ready) begin
            hybrid_ids_select.valid <= 1'b0;
        end
        if (dict_bytes_select.valid && dict_bytes_select.ready) begin
            dict_bytes_select.valid <= 1'b0;
        end
        if (plain_bytes_select.valid && plain_bytes_select.ready) begin
            plain_bytes_select.valid <= 1'b0;
        end
        if (psd_src_select.valid && psd_src_select.ready) begin
            psd_src_select.valid <= 1'b0;
        end
        if (g2t_select.valid && g2t_select.ready) begin
            g2t_select.valid <= 1'b0;
        end
        if (dict_values_select.valid && dict_values_select.ready) begin
            dict_values_select.valid <= 1'b0;
        end
        if (dict_ids_select.valid && dict_ids_select.ready) begin
            dict_ids_select.valid <= 1'b0;
        end
        if (page_last_cross_page_normalizer.valid && page_last_cross_page_normalizer.ready) begin
            page_last_cross_page_normalizer.valid <= 1'b0;
        end
        if (heap_dummy_now && heap_in.ready) begin
            heap_dummy_pending <= 1'b0;
        end

        if (state != ST_IDLE && num_values.ready) begin
            num_values.valid <= 1'b0;
        end
    end
end

assign chunk_confs[0].ready = state == ST_IDLE;
assign page_conf.ready = (state == ST_CONFIGURED)
    && !(is_string && page_conf.data.page_type != PAGE_TYPE_HYBRID && store_busy);

// ------ Stream profiling ------------------------
stream_profile_i profile_in ();
stream_profile_i profile_out();

assign profile.counters.in  = profile_in.counters;
assign profile.counters.out = profile_out.counters;
assign profile_in.stop      = profile.stop;
assign profile_out.stop     = profile.stop;

StreamProfiler inst_profile_in (
    .clk(clk),
    .rst_n(reset_synced),

    .last (in.last),
    .valid(in.valid),
    .ready(in.ready),

    .profile(profile_in)
);

StreamProfiler inst_profile_out (
    .clk(clk),
    .rst_n(reset_synced),

    .last (out.last),
    .valid(out.valid),
    .ready(out.ready),

    .profile(profile_out)
);

`ifdef DEBUG
ila_column_chunk_decoder inst_ila_column_chunk_decoder (
    .clk(clk),
    .probe0(reset_synced),

    .probe1({state}),
    .probe2(last_page),
    .probe3({typ}),
    .probe4(is_string),

    .probe5(chunk_confs[0].valid),
    .probe6(chunk_confs[0].ready),
    .probe7(page_conf.valid),
    .probe8(page_conf.ready),
    .probe9({page_conf.data.page_type}),
    .probe10(page_conf.data.num_values),
    .probe11(page_conf.data.last),

    .probe12({in.valid, in.ready, in.last}),
    .probe13({page_payload.valid, page_payload.ready, page_payload.last}),
    .probe14({decompressor_out.valid, decompressor_out.ready, decompressor_out.last}),
    .probe15({ins[PAGE_TYPE_HYBRID].valid, ins[PAGE_TYPE_HYBRID].ready, ins[PAGE_TYPE_HYBRID].last}),
    .probe16({ins[PAGE_TYPE_DICT].valid, ins[PAGE_TYPE_DICT].ready, ins[PAGE_TYPE_DICT].last}),
    .probe17({ins[PAGE_TYPE_PLAIN].valid, ins[PAGE_TYPE_PLAIN].ready, ins[PAGE_TYPE_PLAIN].last}),

    .probe18({hybrid_ids.valid, hybrid_ids.ready, hybrid_ids.last}),
    .probe19({dict_values.valid, dict_values.ready, dict_values.last}),
    .probe20({dict_ids.valid, dict_ids.ready, dict_ids.last}),
    .probe21({hybrid_typed.valid, hybrid_typed.ready, hybrid_typed.last}),
    .probe22({plain_out.valid, plain_out.ready, plain_out.last}),

    .probe23({psd_in.valid, psd_in.ready, psd_in.last}),
    .probe24({german_strings.valid, german_strings.ready, german_strings.last}),
    .probe25({g2t_typed.valid, g2t_typed.ready, g2t_typed.last}),

    .probe26({outs[OUT_HYBRID].valid, outs[OUT_HYBRID].ready, outs[OUT_HYBRID].last}),
    .probe27({outs[OUT_PLAIN].valid, outs[OUT_PLAIN].ready, outs[OUT_PLAIN].last}),
    .probe28({outs[OUT_STR_PLAIN].valid, outs[OUT_STR_PLAIN].ready, outs[OUT_STR_PLAIN].last}),
    .probe29({inner_out.valid, inner_out.ready, inner_out.last}),
    .probe30({out.valid, out.ready, out.last}),

    .probe31({heap_raw.valid, heap_raw.ready, heap_raw.last}),
    .probe32({heap_in_buf.valid, heap_in_buf.ready, heap_in_buf.last}),
    .probe33({heap_out.valid, heap_out.ready, heap_out.last}),

    .probe34({in_select.valid, out_select.valid, hybrid_ids_select.valid,
              dict_bytes_select.valid, plain_bytes_select.valid, psd_src_select.valid,
              g2t_select.valid, dict_values_select.valid, dict_ids_select.valid}),
    .probe35({decompressor_conf.valid, hybrid_conf.valid, dict_type.valid,
              plain_type.valid, psd_conf.valid, num_values.valid, hybrid_num_values.valid}),

    .probe36(page_last_cross_page_normalizer.valid),
    .probe37(page_last_cross_page_normalizer.ready),
    .probe38(heap_dummy_pending),
    .probe39(heap_dummy_now),
    .probe40(heap_pages_cfgd),
    .probe41(heap_lasts_seen),
    .probe42(heap_offset[31:0]),
    .probe43(store_busy),
    .probe44({ids_group_open, dict_seen})
);
`endif

endmodule
