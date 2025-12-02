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
data32_t remaining_values;


// ------- State declaration (decoders) -----
logic [3:0] rle_width;
rle_count_t rle_count;

bpe_count_t bpe_count;
// bpe_offset is the number of offset bits to add on top of the byte offset
// global to the decoder.
typedef logic[$clog2(NUM_ELEMENTS) * $bits(bit_width_t) - 1:0] bpe_offset_t;
bpe_offset_t bpe_offset;
offset_t bpe_extra;

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
assign packed_databeat_bits = NUM_ELEMENTS * bit_width;
offset_t varint_offset;


// ------- Combinatorial state (decoders) ---
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
// assign varint_in.valid = ((keep_keep[varint_offset+3] && keep_keep[varint_offset+2] && keep_keep[varint_offset+1]) || keep_last_received) && keep_keep[varint_offset];
// assign varint_in.data = '{keep_data[varint_offset+3], keep_data[varint_offset+2], keep_data[varint_offset+1], keep_data[varint_offset]};

// Combinatorial shift values from the varint value used to compute rle_count
// and bpe_count.
logic varint_encoding;
assign varint_encoding = varint_out.data.value[0];
typedef enum logic {
    ENCODING_RLE = 0,
    ENCODING_BPE = 1
} varint_encoding_t;
rle_count_t varint_no_encoding;
assign varint_no_encoding = varint_out.data.value >> 1;
bpe_count_t varint_no_encoding_bytes;
assign varint_no_encoding_bytes = varint_no_encoding  << 3;

// This value always points at the first byte after the varint
offset_t run_data_offset;
assign run_data_offset = varint_offset + varint_out.data.length;

// ------- RLE decoding
tagged_i #(data_t, $bits(rle_count_t)) rle_in ();
ndata_i #(data_t, NUM_ELEMENTS) rle_out ();

ExpandRLE #(data_t, NUM_ELEMENTS) inst_expand_rle (
    .clk(clk),
    .rst_n(reset_synced),

    .in(rle_in),
    .out(rle_out)
);

offset_t rle_offset;
assign rle_offset = state == ST_DECODE_RLE2 ? run_data_offset : offset;

assign rle_in.tag = state == ST_DECODE_RLE2 ? varint_no_encoding : rle_count;
logic[DATA_SIZE - 1:0] rle_in_valid_bits;
logic[DATA_SIZE - 1:0] rle_needs_to_buffer_bits;
generate
for (genvar i = 0; i < DATA_SIZE; i++) begin
    // We need to copy bit-by-bit here as for value sizes that are not
    // multiple of eight, DATA_SIZE will be an over approximation of how many
    // bytes are required. For example, for $bits(data_t) = 18, DATA_SIZE = 3,
    // but we can't access indexes 23:18, only 17:16 for the last byte.
    for (genvar b = 0; b < 8 && i * 8 + b < $bits(data_t); b++) begin
        assign rle_in.data[i * 8 + b] = (i < rle_width) ? data[rle_offset+i][b] : '0;
    end
    assign rle_in_valid_bits[i] = (i >= rle_width) || keep[rle_offset+i];
    assign rle_needs_to_buffer_bits[i] = (i < rle_width && ~keep_keep[rle_offset+i]);
end
endgenerate
assign rle_in.valid = &rle_in_valid_bits && (state == ST_DECODE_RLE || (state == ST_DECODE_RLE2 && varint_out.valid && varint_encoding == ENCODING_RLE));
assign rle_out.ready = state == ST_DECODE_RLE2 && out.ready;
logic rle_needs_more_input;
assign rle_needs_more_input = |rle_needs_to_buffer_bits && ~keep_last_received;

// ------- BPE decoding
bpe_metadata_t bpe_in_meta_data;
valid_i #(bpe_metadata_t) bpe_in_meta ();
assign bpe_in_meta_data.bit_width = bit_width;
assign bpe_in_meta_data.count = bpe_count;
assign bpe_in_meta.valid = state == ST_DECODE_BPE;
assign bpe_in_meta.data = bpe_in_meta_data;

ready_valid_i #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0]) bpe_in ();
ndata_i #(data_t, NUM_ELEMENTS) bpe_out ();

ExpandBPE #(data_t, NUM_ELEMENTS) inst_expand_bpe (
    .in_meta(bpe_in_meta),
    .in(bpe_in),
    .out(bpe_out)
);

// the BPE decoder doesn't look at the keep and last signals.
// assign bpe_in.keep = keep[offset +: $bits(data_t) * NUM_ELEMENTS];
// assign bpe_in.last = bpe_count <= NUM_ELEMENTS;
assign bpe_in.data = bpe_data[offset * 8 + bpe_offset +: $bits(data_t) * NUM_ELEMENTS];
logic[NUM_ELEMENTS * DATA_SIZE - 1:0] bpe_valid_bytes;
logic[NUM_ELEMENTS * DATA_SIZE - 1:0] bpe_needs_to_buffer_bytes;
generate
    for (genvar i = 0; i < NUM_ELEMENTS * DATA_SIZE; i++) begin
        assign bpe_valid_bytes[i] = (i < (packed_databeat_bits / 8)) ? keep[offset + i] : 1;
        assign bpe_needs_to_buffer_bytes[i] = (i < (packed_databeat_bits / 8)) ? ~keep_keep[offset + i] : 0;
    end
endgenerate
assign bpe_in.valid = state == ST_DECODE_BPE && (&(bpe_valid_bytes) || last_received);
assign bpe_out.ready = state == ST_DECODE_BPE && out.ready;
logic bpe_needs_more_input;
// We want to take more input if some of the keep_keep bytes are not high, and
// only if we haven't already consumed the last databeat.
assign bpe_needs_more_input = |bpe_needs_to_buffer_bytes && ~keep_last_received;

// ------- State machine ---------

task store_input(input data8_t[NUM_BYTES - 1:0] data,
                 input logic[NUM_BYTES - 1:0] keep,
                 input logic last,
                 input logic first_half);
    if (first_half) begin
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
    rle_width <= '0;
    varint_offset <= '0;
    varint_in.valid <= 0;
    offset <= '0;
    remaining_values <= '0;
endtask

bpe_count_t next_bpe_count;
assign next_bpe_count = (remaining_values < varint_no_encoding_bytes) ? remaining_values : varint_no_encoding_bytes;
// The value in bpe_count is computed by << 3 the value in the header
// (ignoring the LSB). This means that it'll be a multiple of 8.
// For runs where the number of values encoded in BPE is not a multiple of 8,
// the bpe_count is lower-bounded by the total number of values in the page,
// which is found in in_meta_data.num_values.
//
// If that's the case, we still need to keep track of how many extra values
// have been bit-packed since we need to skip those bytes.
offset_t next_bpe_extra;
assign next_bpe_extra = (remaining_values < varint_no_encoding_bytes) ? varint_no_encoding_bytes - remaining_values : 0;

task goto_decode(input data32_t remaining_values);
    `ifndef SYNTHESIS
    if (~varint_out.valid) begin
        $fatal(1, "Called goto_decode() when varint_out.valid = %b", varint_out.valid);
    end
    `endif

    update_offset(run_data_offset);
    if (varint_encoding == ENCODING_BPE) begin
        state <= ST_DECODE_BPE;

        // Compute BPE properties
        bpe_offset <= 0;
        bpe_count <= next_bpe_count;
        bpe_extra <= next_bpe_extra;

        goto_decode_bpe(run_data_offset, next_bpe_count, next_bpe_extra);
    end else begin
        // Compute RLE properties
        rle_count <= varint_no_encoding;

        if (rle_in.ready && rle_in.valid) begin
            goto_decode_rle2(run_data_offset);
        end else begin
            goto_decode_rle();
        end
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
    end
endtask

logic[$clog2(NUM_ELEMENTS) + $bits(bit_width_t):0] next_bpe_offset;
assign next_bpe_offset = bpe_offset + packed_databeat_bits;

task advance_bpe();
    bpe_count_t next_bpe_count;
    data32_t new_varint_offset;
    `ifndef SYNTHESIS
    if (bpe_count <= NUM_ELEMENTS) begin
        $fatal(1, "Called advance_bpe() on the last databeat for BPE input: %d, %d", bpe_count, NUM_ELEMENTS);
    end
    `endif
    next_bpe_count = bpe_count - NUM_ELEMENTS;

    bpe_count <= next_bpe_count;
    bpe_offset <= next_bpe_offset % 8;
    remaining_values <= remaining_values - NUM_ELEMENTS;
    update_offset(offset + (next_bpe_offset / 8));

    new_varint_offset = (offset + (next_bpe_offset / 8)) + ((next_bpe_count + bpe_extra) * bit_width + (next_bpe_offset % 8)) / 8;
    if (new_varint_offset < NUM_BYTES * 2) begin
        varint_in.data <= data[new_varint_offset];
        varint_in.valid <= &keep[new_varint_offset];
    end
endtask

data32_t next_remaining_values_bpe;
assign next_remaining_values_bpe = remaining_values - bpe_count;

task finish_bpe();
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
    end
endtask

task goto_decode_rle();
    state <= ST_DECODE_RLE;
endtask

task goto_decode_rle2(offset_t offst);
    state <= ST_DECODE_RLE2;
    varint_in.data <= data[offst + rle_width];
    varint_in.valid <= &keep[offst + rle_width];
    varint_offset <= offst + rle_width;
endtask

task goto_decode_bpe(offset_t offst, bpe_count_t bpe_cnt, offset_t bpe_xtra);
    data32_t new_varint_offset;
    new_varint_offset = offst + ((bpe_cnt + bpe_xtra) * bit_width / 8);

    state <= ST_DECODE_BPE;
    if (new_varint_offset < NUM_BYTES * 2) begin
        varint_in.data <= data[new_varint_offset];
        varint_in.valid <= &keep[new_varint_offset];
    end
        varint_offset <= new_varint_offset;
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        reset();
    end else begin
        if (in.ready && in.valid) begin
            store_input(in_data, in_keep, in.last, state == ST_IDLE || state == ST_HEADER);
        end

        case (state)
            ST_IDLE: begin
                if (in_meta.ready && in_meta.valid) begin
                    bit_width <= in_meta_data.bit_width;
                    rle_width <= (in_meta_data.bit_width + 7) >> 3;
                    offset <= in_meta_data.offset;
                    varint_offset <= in_meta_data.offset;
                    remaining_values <= in_meta_data.num_values;
                    
                    if (in.valid) begin
                        state <= ST_HEADER2;
                        varint_in.data <= data[in_meta_data.offset];
                        varint_in.valid <= &keep[in_meta_data.offset];
                    end else begin
                        state <= ST_HEADER;
                    end
                end
            end

            // Here we have received the configuration but we haven't yet
            // received the input. Receiving one databeat may or may not be
            // enough.
            ST_HEADER: begin
                varint_in.data <= data[varint_offset];
                varint_in.valid <= &keep[varint_offset];
                if (varint_out.valid) begin
                    // If we receive input and the varint decoding is done,
                    // we can directly move to the decoder stages.
                    goto_decode(remaining_values);
                end else if (in.valid) begin
                    // Otherwise if we receive input but the decoding is not
                    // done, it means we need even more input to finish
                    // decoding.
                    state <= ST_HEADER2;
                end
            end

            // Here we have received the configuration and one input databeat,
            // but we weren't able to decode the header varint with just that.
            ST_HEADER2: begin
                varint_in.data <= data[varint_offset];
                varint_in.valid <= &keep[varint_offset];
                if (varint_out.valid) begin
                    goto_decode(remaining_values);
                end
            end

            ST_DECODE_RLE: begin
                if (rle_in.ready && rle_in.valid) begin
                    // If the RLE input has been taken by the decoder, move on
                    // and wait for the decoder to be done. In the next state,
                    // we can potentially perform pipelining for consecutive
                    // RLE decodings.
                    goto_decode_rle2(offset);
                end
            end

            // In this state we wait for the RLE decoder to be done.
            ST_DECODE_RLE2: begin
                if (out.ready && rle_out.valid && rle_out.last) begin
                    finish_rle();
                end 
            end

            ST_DECODE_BPE: begin
                if (out.ready && bpe_out.valid) begin
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

// ------- Driving input ---------
logic decoder_needs_input;
assign decoder_needs_input = (
    ((state == ST_DECODE_RLE || state == ST_DECODE_RLE2) && rle_needs_more_input)
 || (state == ST_DECODE_BPE && bpe_needs_more_input)
);
always_comb begin
    // We need to provide default values to prevent latch inference
    in.ready = 0;
    in_meta.ready = 0; 

    case (state)
        ST_IDLE: begin
            in_meta.ready = 1; 
            in.ready = in_meta.valid;
        end

        ST_HEADER, ST_HEADER2:
            in.ready = ~varint_in.valid;

        // TODO: consider if we should also have potentially in.ready high on
        // ST_DECODE_RLE2
        ST_DECODE_RLE, ST_DECODE_BPE: begin
            in.ready = decoder_needs_input;
        end
    endcase
end

// ------- Combinatorial assignments --
always_comb begin
    // Mapping input data, keep and last to combinatorial values
    case (state)
        ST_IDLE, ST_HEADER: begin
            if (in.valid) begin
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

            if (in.valid) begin
                data[NUM_BYTES * 2 - 1:NUM_BYTES] = in_data;
                keep[NUM_BYTES * 2 - 1:NUM_BYTES] = in_keep;
                last_received = in.last;
            end else begin
                data[NUM_BYTES * 2 - 1:NUM_BYTES] = 'x;
                keep[NUM_BYTES * 2 - 1:NUM_BYTES] = '0;
                last_received = keep_last_received;
            end
        end

        default: begin
            data[NUM_BYTES - 1:0] = keep_data[NUM_BYTES - 1:0];
            keep[NUM_BYTES - 1:0] = keep_keep[NUM_BYTES - 1:0];

            if (decoder_needs_input && in.valid) begin
                data[NUM_BYTES * 2 - 1:NUM_BYTES] = in_data;
                keep[NUM_BYTES * 2 - 1:NUM_BYTES] = in_keep;
                last_received = in.last;
            end else begin
                data[NUM_BYTES * 2 - 1:NUM_BYTES] = keep_data[NUM_BYTES * 2 - 1:NUM_BYTES];
                keep[NUM_BYTES * 2 - 1:NUM_BYTES] = keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES];
                last_received = keep_last_received;
            end
        end
    endcase
end

// ------- Driving output --------

always_comb begin
    out.valid = 0;
    out.data = '{default: 'x};
    out.keep = '0;
    out.last = 0;

    case (state)
        ST_DECODE_RLE2: begin
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
    endcase
end

// `ifdef SYNTHESIS
// ila_run_decoder inst_ila_run_decoder (
//     .clk(clk),
//     .probe0(reset_synced),
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
//     .probe9(out.keep),
//     .probe10(out.last),
//
//     .probe11(state),
//     .probe12(offset),
//     .probe13(varint_offset),
//     .probe14(varint_out.valid),
//     .probe15(varint_out.data)
// );
// `endif

endmodule
