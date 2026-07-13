`timescale 1ns / 1ps

import lynxTypes::*;
import libstf::data8_t;

`include "libstf_macros.svh"

/**
 * Packs a byte stream into dense beats across Parquet page boundaries.
 *
 * Each page arrives as its own sub-stream terminated by `in.last`. For every
 * page the decoder FSM pushes one `page_flags` entry whose payload marks
 * whether that page also ends the whole column chunk. Every non-final page
 * last is suppressed, so the underlying `DataNormalizer` keeps its running
 * byte offset and merge register across pages and emits a single,
 * front-packed stream that asserts `last` only on the final beat of the
 * chunk. The leftover, incomplete beat of a page is thus carried in the
 * merge register and packed with the first bytes of the following page.
 *
 * The flags travel through a FIFO rather than a sideband wire because the
 * stream drains decoupled from the FSM: beats of page k may still be in
 * flight while the FSM already configures page k+1. A page's last beat is
 * stalled until its flag is present.
 *
 * Input contract: `in.keep` must be front-contiguous (bytes packed from bit
 * 0; only a beat's tail may be sparse). The heap producer guarantees this —
 * the PlainStringDecoder forwards the dense input page beats verbatim, and
 * dummy flush beats carry keep = 0. The
 * DataNormalizer's compactor (64 chained levels, the design's deepest
 * combinational cloud) would be an identity function on such input, so it is
 * disabled; an assertion below guards the assumption.
 */
module CrossPageNormalizer #(
    parameter NUM_BYTES = AXI_DATA_BITS / 8,
    parameter BARREL_SHIFTER_REGISTER_LEVELS = 2
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s page_last, // #(logic)

    ndata_i.s in, // #(data8_t, NUM_BYTES); in.last marks a page boundary
    ndata_i.m out // #(data8_t, NUM_BYTES); last only on the chunk-final beats
);

ready_valid_i #(logic) page_last_skidded (.*);

SkidBuffer #(logic) inst_page_last_skid (
    .clk(clk),
    .rst_n(rst_n),

    .in(page_last),
    .out(page_last_skidded)
);

// `in.last` (and the flag skid's payload) are don't-care while invalid --
// skid buffers do not reset their payload registers, so both are X right
// after reset. Qualify every use with `in.valid` so `in.ready` never
// becomes a function of an undefined don't-care (the interface asserts
// ready to be defined on every cycle).
logic page_last_valid_or_not_last_beat;
assign page_last_valid_or_not_last_beat = !(in.valid && in.last) || page_last_skidded.valid;
assign page_last_skidded.ready       = in.valid && in.ready && in.last;

// ------ Core normalizer --------------------------------------------------
// Replace the per-page last with a chunk-level last; forward everything else.
ndata_i #(data8_t, NUM_BYTES) merged(clk, rst_n);

assign merged.data  = in.data;
assign merged.keep  = in.keep;
assign merged.valid = in.valid && page_last_valid_or_not_last_beat;
assign merged.last  = in.valid && in.last && page_last_skidded.data;
assign in.ready     = merged.ready && page_last_valid_or_not_last_beat;

// Front-contiguous keep (see input contract in the header). `keep + 1` wraps
// to 0 for a full beat, so the check holds for all packed patterns incl. 0.
assert property (@(posedge clk) disable iff (!rst_n)
    in.valid |-> ((in.keep & (in.keep + 1'b1)) == '0))
else $fatal(1, "CrossPageNormalizer: in.keep not front-contiguous; the compactor-less DataNormalizer requires packed input!");

DataNormalizer #(
    .data_t(data8_t),
    .NUM_ELEMENTS(NUM_BYTES),
    .ENABLE_COMPACTOR(0),
    .BARREL_SHIFTER_REGISTER_LEVELS(BARREL_SHIFTER_REGISTER_LEVELS)
) inst_normalizer (
    .clk(clk),
    .rst_n(rst_n),

    .in(merged),
    .out(out)
);

endmodule
