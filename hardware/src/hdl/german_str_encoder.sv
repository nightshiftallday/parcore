`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;
import parcore::*;

/**
* Encodes a stream of strings into Umbra / "German" fixed-size string views.
*
* Inputs:
*   - in_config : buffer base address and the byte offset of the first string
*                 within the first data beat.
*   - in_lens   : one 32-bit length per string; in_lens.last marks the final
*                 string of the page (the length stream is self-terminating, so
*                 no string count is needed).
*   - in_data   : the concatenated string bytes (already prefix-stripped by the
*                 upstream PlainStringDecoder), STREAM_WIDTH bytes per beat.
*
* Outputs:
*   - out_strings : one german_str_t per input string (length + 4-byte prefix +
*                   8-byte inline payload for short strings, or the buffer
*                   address for long strings).
*   - out_data    : the input byte stream forwarded verbatim, to be written to
*                   the buffer at in_config.buffer_addr. The long-string
*                   addresses emitted on out_strings point into this buffer.
*
* A `Lookahead` widens the view by (INLINE_LEN-1) preview bytes so the full
* 12-byte inline payload of a string can always be read from a single view,
* even when the string starts near the end of a beat.
*
* Each cycle in DO_WORK performs exactly one of:
*   - Path A: a short string with another string still behind it in the same
*     beat -> emit the german struct, keep the current beat.
*   - Path B: the last string that starts in this beat -> emit the german
*     struct AND forward the beat, advancing the view.
*   - Path C: no string starts in this beat (continuation of a long string)
*     -> forward the beat, advance the view.
*   - Flush: all strings emitted but beats remain -> forward beats until last.
* Forwarding a beat with `view_last` set completes the page.
*/

module GermanStringEncoder #(
    parameter int STREAM_WIDTH = AXI_DATA_BITS / 8
) (
    input  logic clk,
    input  logic rst_n,

    ready_valid_i.s     in_config,
    data_i.s            in_lens,
    ndata_i.s           in_data,
    data_i.m            out_strings,
    ndata_i.m           out_data
);

    localparam int INLINE_LEN = 12;
    localparam int PREFIX_LEN = 4;
    localparam int VIEW_WIDTH = STREAM_WIDTH + INLINE_LEN - 1;
    localparam int VIEW_BITS  = $clog2(STREAM_WIDTH);

    // ---------------------------------------------------------------------
    // Lookahead: VIEW_WIDTH-wide sliding view (current beat + preview bytes of
    // the following beat, so a 12-byte inline string never wraps a boundary).
    // ---------------------------------------------------------------------
    ndata_i #(data8_t, VIEW_WIDTH) lookahead_out (.clk(clk), .rst_n(rst_n));

    Lookahead #(
        .data_t       (data8_t),
        .NUM_ELEMENTS (STREAM_WIDTH),
        .PREVIEW_SIZE (INLINE_LEN)
    ) string_lookahead (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (in_data),
        .out   (lookahead_out)
    );

    // ---------------------------------------------------------------------
    // Snapshot of the beat currently being processed. It lags lookahead_out by
    // one beat, so the next beat is already presented when we advance.
    // ---------------------------------------------------------------------
    data8_t [VIEW_WIDTH-1:0]   view_data;
    logic   [STREAM_WIDTH-1:0] view_keep;
    logic                      view_last;

    // ---------------------------------------------------------------------
    // Bookkeeping
    // ---------------------------------------------------------------------
    vaddress_t addr;           // buffer address of the current string's bytes
    int32_t  offset;           // start of the current string, relative to view
    logic    strings_done;     // the in_lens.last length has been consumed

    int32_t length;            // current string length (from in_lens)
    int32_t next_offset;       // start of the next string, relative to view

    assign length      = in_lens.data;
    assign next_offset = offset + length;

    logic [VIEW_BITS-1:0] sp_base; // in-view index of the current string start
    assign sp_base = offset[VIEW_BITS-1:0];

    // ---------------------------------------------------------------------
    // FSM state
    // ---------------------------------------------------------------------
    typedef enum logic { WAIT_CONF, DO_WORK } state_t;
    state_t state;

    // ---------------------------------------------------------------------
    // Per-cycle action decode
    // ---------------------------------------------------------------------
    logic str_in_view;   // a string starts inside the current beat
    logic more_strings;  // strings still to emit
    logic str_here;      // emit a german struct this cycle
    logic crossing;      // emitting this string consumes the rest of the beat
    logic emit_beat;     // forward the current beat and advance the view
    logic is_short;      // string fits inline

    assign str_in_view  = offset < int32_t'(STREAM_WIDTH);
    assign more_strings = !strings_done;
    assign str_here     = str_in_view && more_strings;
    assign crossing     = next_offset >= int32_t'(STREAM_WIDTH);
    // Stay on the beat only for a short string that has another string behind
    // it in the same beat (Path A); every other case finishes this beat.
    assign emit_beat    = !(str_here && !crossing);
    assign is_short     = length <= int32_t'(INLINE_LEN);

    // ---------------------------------------------------------------------
    // Joined handshake. The string output (out_strings/in_lens) and the data
    // output (out_data/lookahead) advance together so neither can emit twice.
    // `data_can_advance` folds in lookahead_out.valid; it is kept OUT of
    // lookahead_out.ready to avoid a combinational valid<->ready loop.
    // ---------------------------------------------------------------------
    logic data_can_advance; // next beat available, or this is the final beat
    logic str_path_ready;
    logic data_path_ready;
    logic transition;

    assign data_can_advance = view_last || lookahead_out.valid;
    assign str_path_ready   = !str_here  || (in_lens.valid && out_strings.ready);
    assign data_path_ready  = !emit_beat || (out_data.ready && data_can_advance);
    assign transition       = str_path_ready && data_path_ready;

    // ---------------------------------------------------------------------
    // German string assembly (Umbra layout).
    // ---------------------------------------------------------------------
    data8_t [INLINE_LEN-1:0] str_bytes;
    always_comb begin : extract_bytes
        for (int i = 0; i < INLINE_LEN; i++)
            str_bytes[i] = (i < length) ? view_data[sp_base + i] : 8'h00;
    end

    data64_t addr_bytes;
    assign addr_bytes = 64'(addr); // zero-extend: addr_t may be < 64 bits

    german_str_t german;
    always_comb begin : build_german
        german        = '0;
        german.length = length;
        for (int i = 0; i < PREFIX_LEN; i++)
            german.prefix[i] = str_bytes[i];
        for (int i = 0; i < 8; i++)
            german.short_str_or_addr[i] = is_short ?
                str_bytes[i + PREFIX_LEN] :
                addr_bytes[i*8 +: 8];
    end

    // ---------------------------------------------------------------------
    // Snapshot load helper
    // ---------------------------------------------------------------------
    task update_view();
        view_data <= lookahead_out.data;
        view_keep <= lookahead_out.keep[STREAM_WIDTH-1:0];
        view_last <= lookahead_out.last;
    endtask

    // ---------------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------------
    // Only accept config once the first data beat is available, so DO_WORK
    // always starts with a valid snapshot.
    assign in_config.ready = (state == WAIT_CONF) && lookahead_out.valid;

    always_ff @(posedge clk) begin : fsm
        if (!rst_n) begin
            state        <= WAIT_CONF;
            offset       <= '0;
            addr         <= '0;
            strings_done <= 1'b0;
            view_keep    <= '0;
            view_last    <= 1'b0;
        end else begin
            case (state)
                WAIT_CONF: begin
                    if (in_config.valid && lookahead_out.valid) begin
                        state        <= DO_WORK;
                        offset       <= 32'(in_config.data.offset);
                        addr         <= in_config.data.buffer_addr;
                        strings_done <= 1'b0;
                        update_view();
                    end
                end
                DO_WORK: begin
                    if (transition) begin
                        if (str_here) begin
                            addr         <= addr + vaddress_t'(length);
                            strings_done <= in_lens.last; // latch on the final length
                        end
                        if (emit_beat) begin
                            if (view_last)
                                state <= WAIT_CONF;
                            else
                                update_view();
                            // Path B (str_here): next string lives in the new
                            // beat. Path C/flush: just slide the view by one beat.
                            offset <= str_here ? (next_offset - int32_t'(STREAM_WIDTH))
                                               : (offset      - int32_t'(STREAM_WIDTH));
                        end else begin
                            offset <= next_offset; // Path A: stay on this beat
                        end
                    end
                end
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // Lookahead consumption. Deliberately independent of lookahead_out.valid
    // (mirrors PlainStringDecoder) so no combinational loop forms; the actual
    // view load in the FSM is additionally gated by data_can_advance.
    // ---------------------------------------------------------------------
    assign lookahead_out.ready =
          ((state == WAIT_CONF) && in_config.valid)
       || ((state == DO_WORK)  && emit_beat && !view_last && out_data.ready && str_path_ready);

    // ---------------------------------------------------------------------
    // String output (one german_str_t per string).
    // ---------------------------------------------------------------------
    assign out_strings.valid = (state == DO_WORK) && str_here && in_lens.valid && data_path_ready;
    assign out_strings.data  = german;
    assign out_strings.keep  = 1'b1;
    assign out_strings.last  = in_lens.last;

    assign in_lens.ready = (state == DO_WORK) && str_here && out_strings.ready && data_path_ready;

    // ---------------------------------------------------------------------
    // Data output (input bytes forwarded verbatim to the buffer).
    // ---------------------------------------------------------------------
    assign out_data.valid = (state == DO_WORK) && emit_beat && data_can_advance && str_path_ready;
    assign out_data.data  = view_data[STREAM_WIDTH-1:0];
    assign out_data.keep  = view_keep;
    assign out_data.last  = view_last;

endmodule