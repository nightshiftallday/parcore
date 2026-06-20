`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;
import parcore::*;

/**
* Parses PLAIN-encoded string pages.
*
* Each string in the page is stored as a 4-byte little-endian length prefix
* followed by that many data bytes. This module:
*   - tracks the byte offset of the *next* length prefix relative to the
*     current stream word ("prefix_offset");
*   - when the prefix lies inside the current word, decodes its 4 bytes,
*     emits the length on out_lens, clears the prefix bytes in the keep mask,
*     and advances prefix_offset by (4 + length);
*   - emits the current word on out_data (with prefix keep-bits cleared) as
*     soon as the next prefix lands beyond the current word;
*   - returns to idle when the last word is consumed.
*
* The input is widened by (LENGTH_PREFIX_LEN-1)=3 preview bytes by `Lookahead`
* so a prefix that straddles a word boundary can still be read from one view.
*
* ASSUMPTIONS (verify against your interface definitions):
*   - ndata_i payload exposes .data (data8_t [WIDTH-1:0]), .keep ([WIDTH-1:0]),
*     .last; data_i / ready_valid_i expose .data/.valid/.ready.
*   - STREAM_WIDTH is a power of two (used for the index truncation of lp_base).
*   - Lookahead's output width equals VIEW_WIDTH (== STREAM_WIDTH + 3).
*/
module PlainStringDecoder #(
    parameter int STREAM_WIDTH = AXI_DATA_BITS / 8,
    parameter NORMALIZER_COMPACTOR_REGISTER_LEVELS      = 1,
    parameter NORMALIZER_BARREL_SHIFTER_REGISTER_LEVELS = 1
) (
    input  logic clk,
    input  logic rst_n,

    output logic err_irq,                          // error handling

    ready_valid_i.s         conf,   // plain_str_decoder_conf_t: num_values + initial byte offset
    ndata_i.s  in,             // incoming plain string column data
    data_i.m               out_lens,       // outgoing string lengths
    ndata_i.m  out_data        // outgoing string bytes (prefixes masked out)
);

    // ---------------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------------
    localparam int LENGTH_PREFIX_LEN = 4;                                   // 4-byte LE length
    localparam int VIEW_WIDTH        = STREAM_WIDTH + LENGTH_PREFIX_LEN - 1; // word + 3 preview bytes
    localparam int VIEW_BITS         = $clog2(STREAM_WIDTH);

    // ---------------------------------------------------------------------
    // Lookahead: produces a VIEW_WIDTH-wide sliding view (word + 3 preview
    // bytes of the following word).
    // ---------------------------------------------------------------------
    ndata_i #(data8_t, VIEW_WIDTH)  lookahead_out  (.clk(clk), .rst_n(rst_n));
    ndata_i #(data8_t, STREAM_WIDTH) raw_out_data (.clk(clk), .rst_n(rst_n));

    Lookahead #(
        .data_t       (data8_t),
        .NUM_ELEMENTS (STREAM_WIDTH),
        .PREVIEW_SIZE (LENGTH_PREFIX_LEN)   // verify: must yield VIEW_WIDTH-wide output
    ) length_lookahead (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (in),
        .out   (lookahead_out)
    );

    // ---------------------------------------------------------------------
    // Snapshot of the word currently being processed.
    //
    // It deliberately lags `lookahead_out` by one word: while we process
    // view_*, the lookahead already presents the NEXT word, so its keep bits
    // are available the moment we advance/refill. (An interface instance
    // cannot be used as a register, which is why these are explicit regs.)
    // ---------------------------------------------------------------------
    data8_t [VIEW_WIDTH-1:0]   view_data;   // word bytes + 3 preview bytes
    logic   [STREAM_WIDTH-1:0] view_keep;   // accumulating keep mask for this word
    logic                      view_last;   // last-word flag of the snapshot

    // ---------------------------------------------------------------------
    // Offset / length bookkeeping
    // ---------------------------------------------------------------------
    logic [31:0] values_remaining;
    logic [31:0] prefix_offset;   // offset of next prefix, relative to current word
    logic [31:0] length;          // decoded length of the current string
    logic [31:0] next_offset;     // prefix_offset + LENGTH_PREFIX_LEN + length

    logic [VIEW_BITS-1:0] lp_base; // in-window index of the prefix (== prefix_offset when in-window)
    assign lp_base = prefix_offset[VIEW_BITS-1:0];

    // Decode the 4-byte little-endian length at the prefix position. The
    // preview bytes guarantee lp_base+3 is always in range, so no wrap/modulo.
    always_comb begin : extract_length
        length = '0;
        for (int i = 0; i < LENGTH_PREFIX_LEN; i++)
            length[i*8 +: 8] = view_data[lp_base + i];
    end

    assign next_offset = prefix_offset + LENGTH_PREFIX_LEN + length;

    // ---------------------------------------------------------------------
    // Derived conditions
    // ---------------------------------------------------------------------
    logic prefix_here;  // next prefix is inside the current word
    logic data_valid;   // prefix position holds real (kept) data, not padding
    logic crossing;     // consuming this string moves us past the current word
    logic have_len;     // a length prefix is ready to emit
    logic at_end;       // prefix position is padding -> end of data
    logic word_only;    // current word has no prefix (pure string-data continuation)

    assign prefix_here = (prefix_offset < STREAM_WIDTH);
    assign data_valid  = view_keep[lp_base];
    assign crossing    = (next_offset > STREAM_WIDTH);
    assign have_len    = prefix_here &&  data_valid;
    assign at_end      = prefix_here && !data_valid;
    assign word_only   = !prefix_here;

    // Mask that clears the in-window bytes of THIS prefix.
    logic [STREAM_WIDTH-1:0] keep_mask_lut;
    assign keep_mask_lut = ~( STREAM_WIDTH'( {LENGTH_PREFIX_LEN{1'b1}} ) << lp_base );

    // Number of prefix bytes that spill into the next word (prefix straddle)
    // and the mask that clears the next word's leading bytes accordingly.
    logic [VIEW_BITS:0]      spill_cnt;
    logic [STREAM_WIDTH-1:0] spill_mask;
    assign spill_cnt  = (prefix_offset + LENGTH_PREFIX_LEN > STREAM_WIDTH)
                      ? (prefix_offset + LENGTH_PREFIX_LEN - STREAM_WIDTH)
                      : '0;
    assign spill_mask = ~( ( STREAM_WIDTH'(1) << spill_cnt ) - 1'b1 );

    // ---------------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------------
    typedef enum logic { WAIT_CONF, DO_WORK } state_t;
    state_t state;

    // Only accept a start offset once the first data word is available, so
    // DO_WORK always begins with a valid snapshot (avoids emitting garbage).
    assign conf.ready = (state == WAIT_CONF) && lookahead_out.valid;

    always_ff @(posedge clk) begin : fsm
        if (!rst_n) begin
            state         <= WAIT_CONF;
            err_irq       <= 1'b0;
            view_keep     <= '0;
            view_last     <= 1'b0;
            // view_data intentionally left unreset (loaded before first use)
        end else begin
            case (state)
                // -------------------------------------------------------
                WAIT_CONF: begin
                    if (conf.valid && lookahead_out.valid) begin
                        state            <= DO_WORK;
                        prefix_offset    <= 32'(conf.data.offset);
                        values_remaining <= conf.data.num_values;
                        view_data     <= lookahead_out.data;
                        view_keep     <= lookahead_out.keep[STREAM_WIDTH-1:0];
                        view_last     <= lookahead_out.last;
                    end
                end
                // -------------------------------------------------------
                DO_WORK: begin
                    // Path A: short string, next prefix stays in this word.
                    if (have_len && !crossing) begin
                        if (out_lens.ready) begin
                            prefix_offset <= next_offset;
                            view_keep     <= view_keep & keep_mask_lut; // drop this prefix
                            values_remaining <= values_remaining - 1;
                        end
                    end
                    // Path B: string runs past the word -> emit word + length,
                    // load next word (clearing any spilled prefix bytes).
                    else if (have_len && crossing) begin
                        if (out_lens.ready && raw_out_data.ready && lookahead_out.valid) begin
                            prefix_offset <= next_offset - STREAM_WIDTH;
                            view_data     <= lookahead_out.data;
                            view_keep     <= lookahead_out.keep[STREAM_WIDTH-1:0] & spill_mask;
                            view_last     <= lookahead_out.last;
                            values_remaining <= values_remaining - 1;
                        end
                    end
                    // Path E: padding reached at a prefix position.
                    else if (at_end) begin
                        if (view_last) begin
                            if (raw_out_data.ready) state <= WAIT_CONF; // emit final word, done
                        end else begin
                            err_irq <= 1'b1;          // padding before last word == malformed
                            state   <= WAIT_CONF;
                        end
                    end
                    // Path C/D: pure string-data continuation (no prefix here).
                    else begin
                        if (view_last) begin
                            if (raw_out_data.ready) state <= WAIT_CONF; // D: emit final word, done
                        end else if (raw_out_data.ready && lookahead_out.valid) begin
                            prefix_offset <= prefix_offset - STREAM_WIDTH; // C: emit + load next
                            view_data     <= lookahead_out.data;
                            view_keep     <= lookahead_out.keep[STREAM_WIDTH-1:0];
                            view_last     <= lookahead_out.last;
                        end
                    end
                end
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // Lookahead consumption (advance underlying input by one word).
    // Note: deliberately does NOT depend on lookahead_out.valid, so no
    // combinational loop forms even if Lookahead derives valid from ready.
    // ---------------------------------------------------------------------
    assign lookahead_out.ready =
          ( (state == WAIT_CONF) && conf.valid )                                                    // first load
       || ( (state == DO_WORK)  && have_len && crossing && out_lens.ready && raw_out_data.ready )   // B
       || ( (state == DO_WORK)  && word_only && !view_last && raw_out_data.ready );                 // C

    // ---------------------------------------------------------------------
    // Length output. On the crossing path it is JOINED with the word output:
    // it only asserts valid when the word can also be taken, so a stall on
    // out_data (or the lookahead) cannot duplicate-emit a length.
    // ---------------------------------------------------------------------
    assign out_lens.valid = (state == DO_WORK) && have_len &&
                            (!crossing || (raw_out_data.ready && lookahead_out.valid));
    assign out_lens.data  = length;
    assign out_lens.keep  = '1;
    assign out_lens.last = values_remaining == 1;

    // ---------------------------------------------------------------------
    // Data output: current word with the prefix keep-bits cleared.
    // Feeds the DataNormalizer which compacts and aligns string bytes.
    // ---------------------------------------------------------------------
    assign raw_out_data.valid = (state == DO_WORK) && (
                 ( have_len && crossing && out_lens.ready && lookahead_out.valid ) // B
              || ( word_only && (view_last || lookahead_out.valid) )               // C/D
              || ( at_end && view_last )                                           // E
            );
    assign raw_out_data.data  = view_data[STREAM_WIDTH-1:0];
    assign raw_out_data.keep  = prefix_here ? (view_keep & keep_mask_lut) : view_keep;
    assign raw_out_data.last  = view_last;

    DataNormalizer #(
        .data_t                     (data8_t),
        .NUM_ELEMENTS               (STREAM_WIDTH),
        .ENABLE_COMPACTOR           (1),
        .COMPACTOR_REGISTER_LEVELS  (NORMALIZER_COMPACTOR_REGISTER_LEVELS),
        .BARREL_SHIFTER_REGISTER_LEVELS(NORMALIZER_BARREL_SHIFTER_REGISTER_LEVELS)
    ) inst_normalizer (
        .clk  (clk),
        .rst_n(rst_n),
        .in   (raw_out_data),
        .out  (out_data)
    );

endmodule