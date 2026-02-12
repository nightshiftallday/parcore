`timescale 1ns / 1ps

`include "libstf_macros.svh"
`include "lynx_macros.svh"

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

    hybrid_page_decoder_config_i.s conf,
    ndata_i.s in,            // #(data8_t, NUM_BYTES)

    ndata_i.m out            // #(data_t, NUM_ELEMENTS)
);

`RESET_RESYNC // Reset pipelining

localparam int NUM_BYTES_OFFSET = 4;

// ------- Run decoder wiring ------
ndata_i #(data8_t, NUM_BYTES) run_decoder_in ();
ndata_i #(data_t, NUM_ELEMENTS) run_decoder_out ();

run_decoder_metadata_t run_decoder_in_meta_data;
ready_valid_i #(run_decoder_metadata_t) run_decoder_in_meta ();
assign run_decoder_in_meta.data = run_decoder_in_meta_data;

RunDecoder #(data_t, NUM_ELEMENTS, NUM_BYTES) inst_run_decoder (
    .clk(clk),
    .rst_n(reset_synced),

    .in(run_decoder_in),
    .in_meta(run_decoder_in_meta),

    .out(run_decoder_out)
);

// ------- Normalizer wiring ------
ready_valid_i #(data64_t) normalize_size ();
NormalizeUntil #(data_t, data32_t, NUM_ELEMENTS) inst_normalize_until (
    .clk(clk),
    .rst_n(reset_synced),

    .size(normalize_size),

    .in(run_decoder_out),
    .out(out)
);

// ------- State machine ---------
typedef enum logic [2:0] {
    ST_IDLE,
    ST_WAIT,
    ST_CONSUME,
    ST_PIPE
} state_t;
state_t state;

offset_t offset, bit_width_offset;
// This is used to handle the edge case where the bit width is contained on
// the last byte of a data page and we need to consume it to get to the first
// byte of the data page we can actually pipe to the run decoder.
valid_i #(bit_width_t) keep_bit_width ();
bit_width_t bit_width;
assign bit_width = keep_bit_width.valid ? keep_bit_width.data : in.data[bit_width_offset];
data32_t num_values;

offset_t actual_offset, next_offset;
assign actual_offset = NUM_BYTES_OFFSET + in.data[NUM_BYTES_OFFSET - 1:0];
assign next_offset = offset - NUM_BYTES;

task reset();
    state <= ST_IDLE;
    offset <= '0;
    bit_width_offset <= '0;
    keep_bit_width.valid <= 1'b0;
    run_decoder_in_meta.valid <= 1'b0;
endtask

task process_first_databeat();
    if (actual_offset >= NUM_BYTES - 1) begin
      offset <= actual_offset;
      state <= ST_CONSUME;
    end else begin
      configure(actual_offset + 1, actual_offset);
    end
endtask

task configure(offset_t offst, offset_t bit_width_offst);
    offset <= offst;
    bit_width_offset <= bit_width_offst;
    run_decoder_in_meta.valid <= 1'b1;
    normalize_size.valid <= 1'b1;
    state <= ST_PIPE;
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        reset();
    end else begin
        case (state)
            ST_IDLE: begin
                if (conf.valid) begin
                    num_values <= conf.num_values;

                    if (in.valid) begin
                        process_first_databeat();
                    end else begin
                        state <= ST_WAIT;
                    end
                end
            end

            ST_WAIT: begin
                if (in.valid) begin
                    process_first_databeat();
                end
            end

            ST_CONSUME: begin
                if (in.valid) begin
                    if (offset == NUM_BYTES - 1) begin
                        keep_bit_width.data = in.data[NUM_BYTES - 1];
                        keep_bit_width.valid = 1;
                        configure(0, 0);
                    end else begin
                        if (next_offset < NUM_BYTES - 1) begin
                            configure(next_offset + 1, next_offset);
                        end else begin
                            offset <= next_offset;
                        end
                    end
                end
            end

            ST_PIPE: begin
                if (run_decoder_in_meta.ready) begin
                    run_decoder_in_meta.valid <= 1'b0;
                end

                if (normalize_size.ready) begin
                    normalize_size.valid <= 1'b0;
                end

                if (out.valid && out.ready && out.last) begin
                    // This is the last databeat for this page, we can reset
                    reset();
                end
            end
        endcase
    end
end

// ------- Driving input ---------
assign conf.ready = state == ST_IDLE;
assign in.ready = state == ST_CONSUME || (state == ST_PIPE && run_decoder_in.ready);

assign run_decoder_in.valid = state == ST_PIPE && in.valid;
assign run_decoder_in.data = in.data;
assign run_decoder_in.keep = in.keep;
assign run_decoder_in.last = in.last;

assign run_decoder_in_meta_data.bit_width = bit_width;
assign run_decoder_in_meta_data.offset = offset;
assign run_decoder_in_meta_data.num_values = num_values;

assign normalize_size.data = num_values;

endmodule
