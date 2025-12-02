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
ndata_i #(data_t, NUM_ELEMENTS) run_decoder_out_inner (), run_decoder_out ();

run_decoder_metadata_t run_decoder_in_meta_data;
ready_valid_i #(run_decoder_metadata_t) run_decoder_in_meta ();
assign run_decoder_in_meta.data = run_decoder_in_meta_data;

RunDecoder #(data_t, NUM_ELEMENTS, NUM_BYTES) inst_run_decoder (
    .clk(clk),
    .rst_n(reset_synced),

    .in(run_decoder_in),
    .in_meta(run_decoder_in_meta),

    .out(run_decoder_out_inner)
);

NDataSkidBuffer #(data_t, NUM_ELEMENTS) inst_skid_buffer_decoder (
    .clk(clk),
    .rst_n(reset_synced),

    .in(run_decoder_out_inner),
    .out(run_decoder_out)
);

// ------- Normalizer wiring ------
ndata_i #(data_t, NUM_ELEMENTS) normalizer_in ();
// This is on purpose 1 bit wider to account for the case where keep is 0xf..f
logic [$clog2(NUM_ELEMENTS):0] normalizer_in_num_values;
assign normalizer_in_num_values = $countones(run_decoder_out.keep);

DataNormalizer #(data_t, NUM_ELEMENTS) data_normalizer_inst (
    .clk(clk),
    .rst_n(reset_synced),

    .in(normalizer_in),
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
logic should_send_meta;

offset_t actual_offset, next_offset;
assign actual_offset = NUM_BYTES_OFFSET + in.data[NUM_BYTES_OFFSET - 1:0];
assign next_offset = offset - NUM_BYTES;

task reset();
    state <= ST_IDLE;
    offset <= 0;
    bit_width_offset <= 0;
    keep_bit_width.valid <= 0;
    should_send_meta <= 0;
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
    should_send_meta <= 1;
    state <= ST_PIPE;
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        reset();
    end else begin
        case (state)
            ST_IDLE: begin
                if (in_meta.valid) begin
                    num_values <= in_meta_data.num_values;

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
                if (run_decoder_in_meta.valid && run_decoder_in_meta.ready) begin
                    should_send_meta <= 0;
                end

                if(normalizer_in.valid && normalizer_in.ready) begin
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

// ------- Driving input ---------
assign in_meta.ready = state == ST_IDLE;
assign in.ready = state == ST_CONSUME || (state == ST_PIPE && run_decoder_in.ready);

assign run_decoder_in.valid = state == ST_PIPE && in.valid;
assign run_decoder_in.data = in.data;
assign run_decoder_in.keep = in.keep;
assign run_decoder_in.last = in.last;

assign run_decoder_in_meta.valid = state == ST_PIPE && should_send_meta && in.valid;
assign run_decoder_in_meta_data.bit_width = bit_width;
assign run_decoder_in_meta_data.offset = offset;
assign run_decoder_in_meta_data.num_values = num_values;

// ------- Mapping run decoder output to normalizer ---------
assign run_decoder_out.ready = normalizer_in.ready;
assign normalizer_in.valid = run_decoder_out.valid;
assign normalizer_in.data = run_decoder_out.data;
assign normalizer_in.keep = run_decoder_out.keep;
assign normalizer_in.last = run_decoder_out.last && num_values <= normalizer_in_num_values;

// `ifdef SYNTHESIS
// ila_hybrid_page_decoder inst_ila_hybrid_page_decoder (
//     .clk(clk),
//     .probe0(reset_resync),
//
//     .probe1(in_meta.ready),
//     .probe2(in_meta.valid),
//     .probe3(in_meta.data),
//
//     .probe4(in.ready),
//     .probe5(in.valid),
//     .probe6(in.last),
//
//     .probe7(out.ready),
//     .probe8(out.valid),
//     .probe9(out.last),
//
//     .probe10(state),
//     .probe11(offset),
//     .probe12(actual_offset),
//     .probe13(bit_width_offset),
//     .probe14(in.data[0]),
//     .probe15(in.data[1]),
//     .probe16(in.data[2]),
//     .probe17(in.data[3]),
//     .probe18(in.data[NUM_BYTES - 1]),
//     .probe19(in.data[NUM_BYTES - 2]),
//     .probe20(in.data[NUM_BYTES - 3]),
//     .probe21(in.data[NUM_BYTES - 4])
// );
// `endif

endmodule
