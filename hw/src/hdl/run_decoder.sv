`timescale 1ns / 1ps

`include "libstf_macros.svh"
`include "lynx_macros.svh"
`include "parcore_types.svh"

import lynxTypes::*;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

module RunDecoder #(
    parameter type data_t,
    parameter NUM_ELEMENTS,
    parameter NUM_BYTES = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_meta, // #(run_decoder_metadata_t)
    ndata_i.s in,            // #(data8_t, NUM_BYTES)

    ndata_i.m out            // #(data_t, NUM_ELEMENTS)
);

`RESET_RESYNC // Reset pipelining

localparam int DATA_SIZE = ($bits(data_t) + 7) / 8;

// ------- Input extraction ------
data8_t[NUM_BYTES - 1:0] in_data;
assign in_data = in.data;
logic[NUM_BYTES - 1:0] in_keep;
assign in_keep = in.keep;

run_decoder_metadata_t in_meta_data;
assign in_meta_data = in_meta.data;

// ------- State declaration -----

typedef enum logic [2:0] {
    ST_IDLE,
    ST_HEADER,
    ST_HEADER2,
    ST_DECODE_RLE,
    ST_DECODE_RLE2,
    ST_DECODE_BPE
} state_t;
state_t state;

data8_t[NUM_BYTES * 2 - 1:0] keep_data;
logic[NUM_BYTES * 2 - 1:0] keep_keep;
logic keep_last_received;
bit_width_t bit_width;
offset_t offset;
offset_t keep_varint_offset;
data32_t remaining_values;


// ------- State declaration (decoders) -----
rle_count_t rle_count;

bpe_count_t bpe_count;
// The value in bpe_count is computed by << 3 the value in the header
// (ignoring the LSB). This means that it'll be a multiple of 8.
// For runs where the number of values encoded in BPE is not a multiple of 8,
// the bpe_count is lower-bounded by the total number of values in the page,
// which is found in in_meta_data.num_values.
//
// If that's the case, we still need to keep track of how many extra values
// have been bit-packed since we need to skip those bytes.
offset_t bpe_extra;
// bpe_offset is the number of offset bits to add on top of the byte offset
// global to the decoder.
logic[$clog2(NUM_ELEMENTS) * $bits(bit_width_t) - 1:0] bpe_offset;
logic bpe_valid;

// ------- Combinatorial state ---
// This is used to keep state regarding the actions to take on the current
// databeat. It combines data from the state machine (keep_* registers)
// and the state of the input interfaces

data8_t[NUM_BYTES * 2 - 1:0] data;
logic[NUM_BYTES * 2 - 1:0] keep;
logic last_received;
// n bits for bit_width_t, + log2(NUM_ELEMENTS) bits
// as this value is the result of bit_width * NUM_ELEMENTS;
logic[$clog2(NUM_ELEMENTS) + $bits(bit_width_t) - 1:0] packed_databeat_bits;
offset_t varint_offset;


// ------- Combinatorial state (decoders) ---
logic [3:0] rle_width;

// This is a bit-level view of the data
logic [NUM_BYTES * 8 * 2 - 1:0] bpe_data;
generate
for (genvar i = 0; i < NUM_BYTES * 2; i++) begin
    assign bpe_data[(i+1) * 8 - 1:i * 8] = data[i];
end
endgenerate

// ------- Header varint decoding
valid_i #(data8_t[VARINT_NUM_BYTES - 1:0]) varint_in ();
valid_i #(varint_t) varint_out ();

VarintDecoder inst_varint_decoder (
    .in(varint_in),
    .out(varint_out)
);

// We must either have:
// - up to 4 valid bytes
// - at least 1 valid byte if we've received last. We assume the input is
// correct.
assign varint_in.valid = ((keep[varint_offset+3] && keep[varint_offset+2] && keep[varint_offset+1]) || last_received) && keep[varint_offset];
assign varint_in.data = '{data[varint_offset+3], data[varint_offset+2], data[varint_offset+1], data[varint_offset]};

// ------- RLE decoding
tagged_i #(data_t, $bits(rle_count_t)) rle_in ();
ndata_i #(data_t, NUM_ELEMENTS) rle_out ();

ExpandRLE #(data_t, NUM_ELEMENTS) inst_expand_rle (
    .clk(clk),
    .rst_n(reset_synced),

    .in(rle_in),
    .out(rle_out)
);

assign rle_in.tag = rle_count;
logic[DATA_SIZE - 1:0] rle_in_valid_bits;
logic[DATA_SIZE - 1:0] rle_needs_to_buffer_bits;
generate
for (genvar i = 0; i < DATA_SIZE; i++) begin
    // We need to copy bit-by-bit here as for value sizes that are not
    // multiple of eight, DATA_SIZE will be an over approximation of how many
    // bytes are required. For example, for $bits(data_t) = 18, DATA_SIZE = 3,
    // but we can't access indexes 23:18, only 17:16 for the last byte.
    for (genvar b = 0; b < 8 && i * 8 + b < $bits(data_t); b++) begin
        assign rle_in.data[i * 8 + b] = (i < rle_width) ? data[offset+i][b] : '0;
    end
    assign rle_in_valid_bits[i] = (i >= rle_width) || keep[offset+i];
    assign rle_needs_to_buffer_bits[i] = (i < rle_width && ~keep_keep[offset+i]);
end
endgenerate
assign rle_in.valid = state == ST_DECODE_RLE && &rle_in_valid_bits;
assign rle_needs_more_input = |rle_needs_to_buffer_bits;

// ------- BPE decoding
bpe_metadata_t bpe_in_meta_data;
valid_i #(bpe_metadata_t) bpe_in_meta ();
assign bpe_in_meta_data.bit_width = bit_width;
assign bpe_in_meta_data.count = bpe_count;
assign bpe_in_meta.valid = bpe_valid;
assign bpe_in_meta.data = bpe_in_meta_data;

data_i #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0]) bpe_in ();
ndata_i #(data_t, NUM_ELEMENTS) bpe_out ();

ExpandBPE #(data_t, NUM_ELEMENTS) inst_expand_bpe (
    .in_meta(bpe_in_meta),
    .in(bpe_in),
    .out(bpe_out)
);

assign bpe_in.data = bpe_data[offset * 8 + bpe_offset +: $bits(data_t) * NUM_ELEMENTS];

// the BPE decoder doesn't look at the keep signal.
// assign bpe_in.keep = keep[offset +: $bits(data_t) * NUM_ELEMENTS];
logic bpe_valid_bytes;
logic bpe_needs_more_input;
always_comb begin
    bpe_valid_bytes = 1'b1;
    bpe_needs_more_input = 1'b0;
    for (int i = 0; i < NUM_ELEMENTS * DATA_SIZE; i++) begin
        if (i < (packed_databeat_bits / 8)) begin
            bpe_valid_bytes &= keep[offset + i];
            bpe_needs_more_input |= ~keep_keep[offset + i];
        end
    end
    bpe_needs_more_input &= ~keep_last_received;
end
assign bpe_in.valid = state == ST_DECODE_BPE && (bpe_valid_bytes || last_received);
assign bpe_in.last = bpe_count <= NUM_ELEMENTS;

// ------- State machine ---------

task store_input(input data8_t[NUM_BYTES - 1:0] data,
                 input logic[NUM_BYTES - 1:0] keep,
                 input logic last,
                 input logic second_half);
    if (~second_half) begin
        keep_data[NUM_BYTES - 1:0] <= data;
        keep_keep[NUM_BYTES - 1:0] <= keep;
    end else begin
        keep_data[NUM_BYTES * 2 - 1:NUM_BYTES] <= data;
        keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES] <= keep;
    end

    keep_last_received <= last;
endtask

task update_offset(input offset_t new_offset);
    // If the new offset is beyond the midpoint of the keep_data buffer, which
    // holds two databeats, then we rewrite the offset and move the second
    // half of the buffer into the first, zeroing the second.
    if (new_offset >= NUM_BYTES) begin
        keep_data[NUM_BYTES - 1:0] <= data[NUM_BYTES * 2 - 1:NUM_BYTES];
        keep_keep[NUM_BYTES - 1:0] <= keep[NUM_BYTES * 2 - 1:NUM_BYTES];

        keep_data[NUM_BYTES * 2 - 1:NUM_BYTES] <=  '{default: 'x};
        keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES] <=  '0;

        offset <= new_offset - NUM_BYTES;
    end else begin
        offset <= new_offset;
    end
endtask

task reset();
    state <= ST_IDLE;
    keep_data <= 'x;
    keep_keep <= '0;
    keep_last_received <= '0;

    bit_width <= '0;
    keep_varint_offset <= '0;
    offset <= '0;
    remaining_values <= '0;
endtask

// This value always points at the first byte after the varint
offset_t run_data_offset;
assign run_data_offset = varint_offset + varint_out.data.length;

// Combinatorial shift values from the varint value used to compute rle_count
// and bpe_count.
logic varint_encoding;
assign varint_encoding = varint_out.data.value[0];
rle_count_t varint_no_encoding;
assign varint_no_encoding = varint_out.data.value >> 1;
bpe_count_t varint_no_encoding_bytes;
assign varint_no_encoding_bytes = varint_no_encoding  << 3;

task goto_decode(input data32_t remaining_values);
    `ifndef SYNTHESIS
    if (~varint_out.valid) begin
        $fatal(1, "Called goto_decode() when varint_out.valid = %b", varint_out.valid);
    end
    `endif

    update_offset(run_data_offset);
    if (varint_encoding) begin
        state <= ST_DECODE_BPE;

        // Compute BPE properties
        bpe_offset <= 0;
        bpe_valid <= 1;
        if (remaining_values < varint_no_encoding_bytes) begin
            bpe_count <= remaining_values;
            bpe_extra <= varint_no_encoding_bytes - remaining_values;
        end else begin
            bpe_count <= varint_no_encoding_bytes;
            bpe_extra <= 0;
        end
    end else begin
        state <= ST_DECODE_RLE;
       
        // Compute RLE properties
        rle_count <= varint_no_encoding;
    end
endtask

data32_t next_remaining_values_rle;
assign next_remaining_values_rle = remaining_values - rle_count;

task finish_rle();
    remaining_values <= next_remaining_values_rle;
    if (next_remaining_values_rle == 0) begin
        reset();
    end else if (varint_out.valid) begin
        // If the varint for the next databeat is already valid and parsed, we can
        // move forward to the next decode, otherwise we store the varint offset
        // which we're trying to decode and move to a state waiting for more input).
        goto_decode(next_remaining_values_rle);
    end else begin
        // If ~varint_out.valid we need to fetch more input to
        // satisfy it.
        state <= ST_HEADER2;
        keep_varint_offset <= varint_offset;
    end
endtask

logic[$clog2(NUM_ELEMENTS) + $bits(bit_width_t):0] next_bpe_offest;
assign next_bpe_offest = bpe_offset + packed_databeat_bits;

task advance_bpe();
    `ifndef SYNTHESIS
    if (bpe_count <= NUM_ELEMENTS) begin
        $fatal(1, "Called advance_bpe() on the last databeat for BPE input", varint_offset, offset);
    end
    `endif

    bpe_count <= bpe_count - NUM_ELEMENTS;
    bpe_offset <= next_bpe_offest % 8;
    remaining_values <= remaining_values - NUM_ELEMENTS;
    update_offset(offset + (next_bpe_offest / 8));
endtask

data32_t next_remaining_values_bpe;
assign next_remaining_values_bpe = remaining_values - bpe_count;

task finish_bpe();
    bpe_valid <= 0;
    remaining_values <= next_remaining_values_bpe;

    if (next_remaining_values_bpe == 0) begin
        reset();
    end else if (varint_out.valid) begin
        // If the varint for the next databeat is already valid and parsed, we can
        // move forward to the next decode, otherwise we store the varint offset
        // which we're trying to decode and move to a state waiting for more input).
        goto_decode(next_remaining_values_bpe);
    end else begin
        // If ~varint_out.valid we need to fetch more input to
        // satisfy it.
        state <= ST_HEADER2;
        keep_varint_offset <= varint_offset;
    end
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        reset();
    end else begin
        case (state)
            ST_IDLE: begin
                if (in_meta.ready && in_meta.valid) begin
                    bit_width <= in_meta_data.bit_width;
                    offset <= in_meta_data.offset;
                    keep_varint_offset <= in_meta_data.offset;
                    remaining_values <= in_meta_data.num_values;
                    
                    if (in.ready && in.valid) begin
                        store_input(in_data, in_keep, in.last, 0);
                    end

                    // NOTE: we must make sure this input we're on
                    // is valid, otherwise we cannot consider the varint value
                    // valid either.
                    if (in.valid && varint_out.valid) begin
                        // We received the meta, input and managed to parse
                        // the varint aleady. Move to decoding immediately.
                        goto_decode(in_meta_data.num_values);
                    end else if (in.ready && in.valid) begin
                        // If we're already to read the input, but
                        // ~varint_out.valid, it means that we don't have
                        // enough bytes to decode the varint header.
                        state <= ST_HEADER2;
                    end else begin
                        // We haven't received any input whatsoever.
                        // Move in a dedicated state for awaiting that.
                        state <= ST_HEADER;
                    end
                end
            end

            // Here we have received the configuration but we haven't yet
            // received the input. Receiving one databeat may or may not be
            // enough.
            ST_HEADER: begin
                if (in.ready && in.valid) begin
                    store_input(in_data, in_keep, in.last, 0);
                end

                if (varint_out.valid) begin
                    // If we receive input and the varint decoding is done,
                    // we can directly move to the decoder stages.
                    goto_decode(remaining_values);
                end else if (in.ready && in.valid) begin
                    // Otherwise if we receive input but the decoding is not
                    // done, it means we need even more input to finish
                    // decoding.
                    state <= ST_HEADER2;
                end
            end

            // Here we have received the configuration and one input databeat,
            // but we weren't able to decode the header varint with just that.
            ST_HEADER2: begin
                if (in.ready && in.valid) begin
                    store_input(in_data, in_keep, in.last, 1);
                end

                if (varint_out.valid) begin
                    goto_decode(remaining_values);
                end
            end

            ST_DECODE_RLE: begin
                if (in.ready && in.valid) begin
                    store_input(in_data, in_keep, in.last, 1);
                end

                if (rle_out.ready && rle_out.valid && rle_out.last) begin
                    finish_rle();
                end else if (rle_in.ready && rle_in.valid) begin
                    // If it's not the last databeat for this decoding, move
                    // on to the ST_DEOCDE_RLE2 state where we wait for that to
                    // happen.
                    state <= ST_DECODE_RLE2;
                    keep_varint_offset <= varint_offset;
                end
            end

            // In this state we wait for the RLE decoder to be done.
            ST_DECODE_RLE2: begin
                if (rle_out.ready && rle_out.valid && rle_out.last) begin
                  finish_rle();
                end
            end

            ST_DECODE_BPE: begin
                if (in.ready && in.valid) begin
                    store_input(in_data, in_keep, in.last, 1);
                end

                if (bpe_out.ready && bpe_out.valid) begin
                    if (bpe_out.last) begin
                        finish_bpe();
                    end else begin
                        advance_bpe();
                    end
                end
            end
        endcase
    end
end

// ------- Combinatorial assignments --

always_comb begin
    if (reset_synced) begin
        packed_databeat_bits = NUM_ELEMENTS * bit_width;

        // Driving varint_offset
        if (state == ST_IDLE && in_meta.valid) begin
            varint_offset = in_meta_data.offset;
        end else if (state == ST_DECODE_RLE && rle_in.ready && rle_in.valid) begin
            // When decoding RLE, can move forward the offset if we've configured
            // the RLE expander, so we can achieve full throughput for consecutive
            // RLE runs.
            varint_offset = offset + rle_width;
        end else if (state == ST_DECODE_BPE && bpe_out.ready && bpe_out.valid && bpe_out.last) begin
            // When decoding BPE, can move forward the offset if we're done flushing
            // the last BPE databeat, so we can achieve full throughput for
            // consecutive runs.

            // The increment on a final BPE databeat width is given by:
            //     ((bpe_count + bpe_extra) * bit_width + bpe_offset) / 8
            varint_offset = offset + ((bpe_count + bpe_extra) * bit_width + bpe_offset) / 8;
        end else begin
            varint_offset = keep_varint_offset;
        end

        // Mapping input data, keep and last to combinatorial values
        case (state)
            ST_IDLE, ST_HEADER: begin
                if (in.ready && in.valid) begin
                    data[NUM_BYTES - 1:0] = in_data;
                    keep[NUM_BYTES - 1:0] = in_keep;
                    data[NUM_BYTES * 2 - 1:NUM_BYTES] = '0;
                    keep[NUM_BYTES * 2 - 1:NUM_BYTES] = '0;
                    last_received = in.last;
                end else begin
                    data = '0;
                    keep = '0;
                    last_received = 0;
                end
            end

            ST_HEADER2: begin
                data[NUM_BYTES - 1:0] = keep_data[NUM_BYTES - 1:0];
                keep[NUM_BYTES - 1:0] = keep_keep[NUM_BYTES - 1:0];

                if (in.ready && in.valid) begin
                    data[NUM_BYTES * 2 - 1:NUM_BYTES] = in_data;
                    keep[NUM_BYTES * 2 - 1:NUM_BYTES] = in_keep;
                    last_received = in.last;
                end else begin
                    data[NUM_BYTES * 2 - 1:NUM_BYTES] = '0;
                    keep[NUM_BYTES * 2 - 1:NUM_BYTES] = '0;
                    last_received = keep_last_received;
                end
            end

            ST_DECODE_RLE, ST_DECODE_BPE: begin
                data[NUM_BYTES - 1:0] = keep_data;
                keep[NUM_BYTES - 1:0] = keep_keep;

                if (in.ready && in.valid) begin
                    data[NUM_BYTES * 2 - 1:NUM_BYTES] = in_data;
                    keep[NUM_BYTES * 2 - 1:NUM_BYTES] = in_keep;
                    last_received = in.last;
                end else begin
                    data[NUM_BYTES * 2 - 1:NUM_BYTES] = keep_data[NUM_BYTES * 2 - 1:NUM_BYTES];
                    keep[NUM_BYTES * 2 - 1:NUM_BYTES] = keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES];
                    last_received = keep_last_received;
                end
            end

            default begin
              data = keep_data;
              keep = keep_keep;
              last_received = keep_last_received;
            end
        endcase
    end
end

// ------- Driving input ---------

always_comb begin
    in_meta.ready = state == ST_IDLE && reset_synced;
    // We need to provide default values to prevent latch inference
    in.ready = 0;

    case (state)
        ST_IDLE: begin
            in.ready = in_meta.ready && in_meta.valid;
        end

        ST_HEADER, ST_HEADER2: begin
            in.ready = 1;
        end

        ST_DECODE_RLE: begin
            // We need to read more input to provide enough data to the RLE
            // expander.
            in.ready = rle_needs_more_input;
        end

        ST_DECODE_RLE2: begin
            // We are waiting for the RLE decoder to complete, which doesn't
            // need any input once instantiated.
            in.ready = 0;
        end

        ST_DECODE_BPE: begin
            in.ready = bpe_needs_more_input;
        end
    endcase
end

// ------- Driving decoders state ---------

always_comb begin
    rle_width = (bit_width + 7) >> 3;
    rle_out.ready = state >= ST_DECODE_RLE && state <= ST_DECODE_RLE2 && out.ready;

    bpe_out.ready = state == ST_DECODE_BPE && out.ready;
end

// ------- Driving output --------

always_comb begin
    case (state)
        ST_DECODE_RLE, ST_DECODE_RLE2: begin
          out.valid = rle_out.valid;
          out.data = rle_out.data;
          out.keep = rle_out.keep;
          out.last = rle_out.last;
        end

        ST_DECODE_BPE: begin
          out.valid = bpe_out.valid;
          out.data = bpe_out.data;
          out.keep = bpe_out.keep;
          out.last = bpe_out.last;
        end

        default: begin
            out.valid = 0;
            out.data = '{default: 'x};
            out.keep = '0;
            out.last = 0;
        end
    endcase
end

endmodule
