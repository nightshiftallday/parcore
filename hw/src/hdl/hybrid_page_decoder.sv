`timescale 1ns / 1ps

`include "libstf_macros.svh"
`include "lynx_macros.svh"
`include "parcore_types.svh"

import lynxTypes::*;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

// This module reads the first 4 bytes of the input as an uint32, call it n.
// Then, it computes the offset n+4 and takes in as much input as needed to
// obtain a databeat where the byte at n+4+2 is valid. The byte at n+4+2 is
// parsed as the bit_width. The metadata (bit_width, offest, num_values) is
// then piped to the RunDecoder component, along with the input (including
// current databeat). Num values comes from the in_meta stream.
module HybridPageDecoder #(
    parameter type data_t,
    parameter NUM_ELEMENTS,
    parameter NUM_BYTES = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_meta, // #(page_metadata_t)
    ndata_i.s in,            // #(data8_t, NUM_BYTES)

    ndata_i.m out            // #(data_t, NUM_ELEMENTS)
);

`RESET_RESYNC // Reset pipelining

localparam int NUM_BYTES_OFFSET = 4;

// ------- Input extraction ------
page_metadata_t in_meta_data;
assign in_meta_data = in_meta.data;

// ------- Run decoder wiring ------
ndata_i #(data8_t, NUM_BYTES) run_decoder_in ();
ndata_i #(data_t, NUM_ELEMENTS) run_decoder_out ();

run_decoder_metadata_t run_decoder_in_meta_data;
ready_valid_i #(run_decoder_metadata_t) run_decoder_in_meta ();
assign run_decoder_in_meta.data = run_decoder_in_meta_data;

// ------- Normalizer wiring ------
ndata_i #(data_t, NUM_ELEMENTS) normalizer_in ();

// ------- Combinatorial state ---
offset_t offset;
// This is on purpose 1 bit wider to account for the case where keep is 0xf..f
logic [$clog2(NUM_ELEMENTS):0] normalizer_in_num_values;

// ------- State machine ---------
typedef enum logic {
    ST_CONSUME,
    ST_PIPE
} state_t;
state_t state;

logic configured;
offset_t keep_offset;
bit_width_t bit_width;
data32_t num_values;

task reset();
    state <= ST_CONSUME;
    configured <= 0;
    keep_offset <= 0;
    bit_width <= 0;
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        reset();
    end else begin
        case (state)
            ST_CONSUME: begin
                if (in.valid) begin
                    // $display("in consume, valid: %d, ready: %d, configured: %d, offset: %d, bit_width: %d", in.valid, in.ready, configured, offset, bit_width);

                    if (~configured) begin
                        // If we can peek at the input databeat, as well as read the
                        // metadata, then we can configure the module and wait for the
                        // offset to fall within the desired range. Then, we can start
                        // piping input to the run decoder
                        if (in_meta.ready && in_meta.valid) begin
                            num_values <= in_meta_data.num_values;

                            if (in.ready) begin
                                keep_offset <= offset - NUM_BYTES;
                            end else begin
                                keep_offset <= offset;
                            end

                            configured <= 1;
                        end
                    end else begin
                        if (offset <= NUM_BYTES-1) begin
                            // edge case where offset is such that the last byte
                            // is the bit width, so we should consume this input
                            // and move to ST_PIPE
                            bit_width <= in.data[offset];
                            keep_offset <= (offset + 1) % NUM_BYTES;
                            state <= ST_PIPE;
                        end else begin
                            keep_offset <= offset - NUM_BYTES;
                        end
                    end
                end
            end

            ST_PIPE: begin
                if (run_decoder_in_meta.valid && run_decoder_in_meta.ready) begin
                    configured <= 0;
                end

                if(normalizer_in.valid && normalizer_in.ready) begin
                    // $display("normalizer took in: %x %b, remaining %d values", normalizer_in.keep, normalizer_in.last, num_values);
                    // $display("num_values: %d, normalizer_in_num_values: %d", num_values, normalizer_in_num_values);

                    // NOTE: it is safe to tamper with num_values here, which is
                    // used in the otuput for run_decoder_in_meta, as we're
                    // assuming that the transaction with the run decoder has
                    // already happened (or is happening in this cycle) when we
                    // start receiving output.
                    if (num_values >= normalizer_in_num_values) begin
                        num_values <= num_values - normalizer_in_num_values;
                      end
                end

                if (out.valid && out.ready && out.last) begin
                    // This is the last databeat for this page, we can reset
                    reset();
                end
            end
        endcase
    end
end

// ------- Run decoder wiring ---------
RunDecoder #(data_t, NUM_ELEMENTS, NUM_BYTES) inst_run_decoder (
    .clk(clk),
    .rst_n(reset_synced),

    .in(run_decoder_in),
    .in_meta(run_decoder_in_meta),

    .out(run_decoder_out)
);

// ------- Mapping run decoder output to normalizer ---------

always_comb begin
    normalizer_in_num_values = $countones(run_decoder_out.keep);

    run_decoder_out.ready = normalizer_in.ready;
    normalizer_in.valid = run_decoder_out.valid;
    normalizer_in.data = run_decoder_out.data;
    normalizer_in.keep = run_decoder_out.keep;
    normalizer_in.last = run_decoder_out.last && num_values <= normalizer_in_num_values;
end

// ------- Normalizer wiring ---------

DataNormalizer #(data_t, NUM_ELEMENTS) data_normalizer_inst (
    .clk(clk),
    .rst_n(reset_synced),

    .in(normalizer_in),
    .out(out)
);

// ------- Driving combinatorial state ---

always_comb begin
    if (state == ST_CONSUME && in.valid && ~configured) begin
        offset = in.data[NUM_BYTES_OFFSET - 1:0] + NUM_BYTES_OFFSET;
    end else begin
        offset = keep_offset;
    end
end

// ------- Driving input ---------

always_comb begin
    // We only accept metadata input if we're ready to store it and process
    // it. Refer to the state machine code.
    in_meta.ready = state == ST_CONSUME && in.valid && ~configured && reset_synced;

    case (state)
        ST_CONSUME: begin
            if (~configured) begin
                in.ready = in_meta.valid && offset >= NUM_BYTES-1;
            end else begin
                in.ready = offset >= NUM_BYTES-1;
            end
            run_decoder_in.valid = 0;
        end

        ST_PIPE: begin
            in.ready = run_decoder_in.ready;
            run_decoder_in.valid = in.valid;
        end
    endcase

    run_decoder_in.data = in.data;
    run_decoder_in.keep = in.keep;
    run_decoder_in.last = in.last;

    run_decoder_in_meta.valid = state == ST_PIPE && configured;
    run_decoder_in_meta_data.bit_width = bit_width;
    run_decoder_in_meta_data.offset = offset;
    run_decoder_in_meta_data.num_values = num_values;
end

endmodule
