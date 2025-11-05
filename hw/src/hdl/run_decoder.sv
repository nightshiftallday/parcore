`timescale 1ns / 1ps

`include "axi_macros.svh"
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
bit_width_t keep_bit_width;
offset_t keep_varint_offset;
offset_t keep_offset;
data32_t remaining_values;
logic[VARINT_NUM_BITS - 1:0] keep_header;

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
bpe_count_t bpe_extra;
// bpe_offset is the number of offset bits to add on top of the byte offset
// global to the decoder.
logic[$clog2($bits(data_t)) * $clog2(NUM_ELEMENTS) - 1:0] bpe_offset;
logic bpe_valid;

// ------- Combinatorial state ---
// This is used to keep state regarding the actions to take on the current
// databeat. It combines data from the state machine (keep_* registers)
// and the state of the input interfaces

data8_t[NUM_BYTES * 2 - 1:0] data;
logic[NUM_BYTES * 2 - 1:0] keep;
logic last_received;
bit_width_t bit_width;
// n bits for bit_width_t, + log2(NUM_ELEMENTS) bits
// as this value is the result of bit_width * NUM_ELEMENTS;
logic[$clog2(NUM_ELEMENTS) + $bits(bit_width_t) - 1:0] packed_databeat_bits;
offset_t varint_offset;
offset_t offset;
logic [VARINT_NUM_BITS - 1:0] header;


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

VarintDecoder varint_decoder_inst (
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
bitdata_i #($bits(data_t), rle_count_t) rle_in ();
ndata_i #(data_t, NUM_ELEMENTS) rle_out ();

ExpandRLE #($bits(data_t), NUM_ELEMENTS) expand_rle_inst (
    .clk(clk),
    .rst_n(rst_n),

    .in(rle_in),
    .out(rle_out)
);

assign rle_in.data = '0;
assign rle_in.meta = rle_count;
logic[$bits(data_t) / 8 - 1:0] rle_in_valid_bits;
logic[$bits(data_t) / 8 - 1:0] rle_needs_to_buffer_bits;
generate
for (genvar i = 0; i < $bits(data_t) / 8; i++) begin
    assign rle_in.data[(i + 1) * 8 - 1:i * 8] = (i < rle_width) ? data[offset+i] : '0;
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

ExpandBPE #(data_t, NUM_ELEMENTS) expand_bpe_inst (
    .clk(clk),
    .rst_n(rst_n),

    .in_meta(bpe_in_meta),
    .in(bpe_in),
    .out(bpe_out)
);

assign bpe_in.data = bpe_data[offset * 8 + bpe_offset +: $bits(data_t) * NUM_ELEMENTS];

// the BPE decoder doesn't look at the keep signal.
// assign bpe_in.keep = keep[offset +: $bits(data_t) * NUM_ELEMENTS];
// TODO: account for bpe_offset and odd bit widths in here, by checking +1
// bytes when needed.
logic bpe_valid_bytes;
logic bpe_needs_more_input;
always_comb begin
    bpe_valid_bytes = 1'b1;
    bpe_needs_more_input = 1'b0;
    for (int i = 0; i < NUM_ELEMENTS * $bits(data_t) / 8; i++) begin
        if (i < (packed_databeat_bits / 8)) begin
            bpe_valid_bytes &= keep[offset + i];
            bpe_needs_more_input |= ~keep_keep[offset + i];
        end
    end
    // TODO: consider possible edge cases by using keep_last_received and not
    // last_receive. Should be fine at first thought.
    bpe_needs_more_input &= ~keep_last_received;
end
assign bpe_in.valid = state == ST_DECODE_BPE && (bpe_valid_bytes || last_received);

assign bpe_in.last = bpe_count <= NUM_ELEMENTS;

// ------- State machine ---------

task store_input(input data8_t[NUM_BYTES - 1:0] data,
                 input logic[NUM_BYTES - 1:0] keep,
                 input logic last,
                 input logic second_half);
    // $display("!!!!!!!!!! storing in %d, %x, %x, %b", second_half, data, keep ,last);
    if (~second_half) begin
        keep_data[NUM_BYTES - 1:0] <= data;
        keep_keep[NUM_BYTES - 1:0] <= keep;
    end else begin
        keep_data[NUM_BYTES * 2 - 1:NUM_BYTES] <= data;
        keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES] <= keep;
    end

    keep_last_received <= last;
endtask

task trim_input(input offset_t new_varint_offset, input offset_t new_offset);
    if (new_offset >= NUM_BYTES) begin
        keep_data[NUM_BYTES - 1:0] <= data[NUM_BYTES * 2 - 1:NUM_BYTES];
        keep_keep[NUM_BYTES - 1:0] <= keep[NUM_BYTES * 2 - 1:NUM_BYTES];

        keep_data[NUM_BYTES * 2 - 1:NUM_BYTES] <=  '{default: '0};
        keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES] <=  '0;

        keep_offset <= new_offset - NUM_BYTES;
        if (new_varint_offset >= NUM_BYTES) begin
            keep_varint_offset <= new_varint_offset - NUM_BYTES;
        end else begin
            // NOTE: varint_offset when trimming input will not be used in the
            // next cycle, as we're either:
            // - reading a RLE encoding, then we're reading the data at this
            // point, since we've just incremented the offset.
            // - reaing a BPE encoding, then we're also reading the data.
            //
            // In both cases, varint_offset will be computed by combinatorial
            // logic so we can have instant transitions between states.
            // The only case in which keep_varint_offset is used and actually
            // read, is when we haven't been able to parse the varint in the
            // previous cycle, and we're now waiting for more input for the
            // varint. But note that in this circumstance, we won't be advancing
            // the offset, so we won't end up in the trim_input routine in the
            // first place.
            keep_varint_offset <= 0;
        end
    end
endtask

task update_offset(input offset_t varint_offset, input offset_t offset);
    `ifndef SYNTHESIS
    if (varint_offset > offset) begin
        $fatal(1, "Attempt to set varint_offset after offset. varint_offset: %d, offset: %d", varint_offset, offset);
    end
    `endif

    keep_varint_offset <= varint_offset;
    keep_offset <= offset;
    trim_input(varint_offset, offset);
endtask

task reset();
    // $display("resetting");
    state <= ST_IDLE;
    keep_data <= '0;
    keep_keep <= '0;
    keep_last_received <= '0;

    keep_bit_width <= '0;
    keep_varint_offset <= '0;
    keep_offset <= '0;
    remaining_values <= '0;

    keep_header <= '0;
endtask

task goto_decode(input data32_t remaining_values);
    `ifndef SYNTHESIS
    if (~varint_out.valid) begin
        $fatal(1, "Called goto_decode() when varint_out.valid = %b", varint_out.valid);
    end
    `endif

    keep_header <= varint_out.data.value;

    if (varint_out.data.value[0]) begin
        state <= ST_DECODE_BPE;
        update_offset(varint_offset, varint_offset + varint_out.data.length);

        if (remaining_values < (varint_out.data.value >> 1 << 3)) begin
            // $display("performing BPE (1) %d", remaining_values);
            bpe_count <= remaining_values;
            bpe_extra <= (varint_out.data.value >> 1 << 3) - remaining_values;
        end else begin
            // $display("performing BPE (2) %d", varint_out.data.value >> 1 << 3);
            bpe_count <= varint_out.data.value >> 1 << 3;
            bpe_extra <= 0;
        end

        bpe_offset <= 0;
        bpe_valid <= 1;
    end else begin
        // $display("performing LRE %d", varint_out.data.value >> 1);
        state <= ST_DECODE_RLE;
        update_offset(varint_offset, varint_offset + varint_out.data.length);
       
        // Compute RLE properties
        rle_count <= varint_out.data.value >> 1;
    end
endtask

task finish_rle();
    remaining_values <= remaining_values - rle_count;
    if (remaining_values <= rle_count) begin
        reset();
    end else if (varint_out.valid) begin
        // If the varint for the next databeat is already valid and parsed, we can
        // move forward to the next decode, otherwise we store the varint offset
        // which we're trying to decode and move to a state waiting for more input).
        goto_decode(remaining_values - rle_count);
    end else begin
        // If ~varint_out.valid we need to fetch more input to
        // satisfy it.
        state <= ST_HEADER2;
        keep_varint_offset <= varint_offset;
    end
endtask

task advance_bpe();
    `ifndef SYNTHESIS
    if (bpe_count <= NUM_ELEMENTS) begin
        $fatal(1, "Called advance_bpe() on the last databeat for BPE input", varint_offset, offset);
    end
    `endif

    bpe_count <= bpe_count - NUM_ELEMENTS;
    bpe_offset <= bpe_offset + packed_databeat_bits % 8;
    remaining_values <= remaining_values - NUM_ELEMENTS;
    update_offset(varint_offset, offset + ((bpe_offset + packed_databeat_bits) / 8));
endtask

task finish_bpe();
    bpe_valid <= 0;
    remaining_values <= remaining_values - bpe_count;

    if (remaining_values <= bpe_count) begin
        reset();
    end else if (varint_out.valid) begin
        // If the varint for the next databeat is already valid and parsed, we can
        // move forward to the next decode, otherwise we store the varint offset
        // which we're trying to decode and move to a state waiting for more input).
        goto_decode(remaining_values - bpe_count);
    end else begin
        // If ~varint_out.valid we need to fetch more input to
        // satisfy it.
        state <= ST_HEADER2;
        keep_varint_offset <= varint_offset;
    end
endtask

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        reset();
    end else begin
        // $display("in state: %d, in.ready: %d, in.valid: %d, out.ready: %d, out.valid: %d, offset: %d", state, in.ready, in.valid, out.ready, out.valid, offset);

        case (state)
            ST_IDLE: begin
                if (in_meta.ready && in_meta.valid) begin
                    keep_bit_width <= in_meta_data.bit_width;
                    keep_varint_offset <= in_meta_data.offset;
                    keep_offset <= in_meta_data.offset;
                    remaining_values <= in_meta_data.num_values;
                    
                    if (in.ready && in.valid) begin
                        store_input(in_data, in_keep, in.last, 0);
                    end

                    // NOTE: we must make sure this input we're on
                    // is valid, otherwise we 
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
                // $display("| in BPE, bit_width: %d", bit_width);
                // $display("| bpe_count: %d, offset: %d, bpe_offset: %d, bpe_in.data: %x", bpe_count, offset, bpe_offset, bpe_in.data);
                // $display("| bpe_in.valid: %d, bpe_in.ready: %d", bpe_in.valid, bpe_in.ready);
                // $display("| bpe_out.valid: %d, bpe_out.ready: %d, bpe_out.keep: %x", bpe_out.valid, bpe_out.ready, bpe_out.keep);

                if (in.ready && in.valid) begin
                    store_input(in_data, in_keep, in.last, 1);
                end

                if (bpe_out.ready && bpe_out.valid) begin
                    // $display("putting out bpe batch, %b, remaining: %d, bpe_count: %d", bpe_out.last, remaining_values, bpe_count);
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
    if (state == ST_IDLE && in_meta.ready && in_meta.valid) begin
        // On the initial beat we may already have received metadata
        bit_width = in_meta_data.bit_width;
        offset = in_meta_data.offset;
    end else begin
        bit_width = keep_bit_width;
        offset = keep_offset;
    end
    packed_databeat_bits = NUM_ELEMENTS * bit_width;

    // Driving varint_offset
    if (state == ST_IDLE && in_meta.ready && in_meta.valid) begin
        varint_offset = in_meta_data.offset;
    end else if (state == ST_DECODE_RLE && rle_in.ready && rle_in.valid) begin
        // When decoding RLE, can move forward the offset if we've configured
        // the RLE expander, so we can achieve full throughput for consecutive
        // RLE runs.
        varint_offset = keep_offset + rle_width;
    end else if (state == ST_DECODE_BPE && bpe_out.ready && bpe_out.valid && bpe_out.last) begin
        // When decoding BPE, can move forward the offset if we're done flushing
        // the last BPE databeat, so we can achieve full throughput for
        // consecutive runs.

        // The increment on a final BPE databeat width is given by:
        //     ((bpe_count + bpe_extra) * bit_width + bpe_offset) / 8
        varint_offset = keep_offset + ((bpe_count + bpe_extra) * bit_width + bpe_offset) / 8;
    end else begin
        varint_offset = keep_varint_offset;
    end

    if (state <= ST_HEADER2 && varint_out.valid) begin
        header = varint_out.data.value;
    end else if (state >= ST_DECODE_RLE && state <= ST_DECODE_RLE2 && varint_out.valid) begin
        // When decoding RLE, we may move forward the offset,
        // thus the header will change
        header = varint_out.data.value;
    end else begin
        header = keep_header;
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

// ------- Driving input ---------

always_comb begin
    in_meta.ready = state == ST_IDLE;

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
    in_meta.ready = state == ST_IDLE && rst_n;

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
            out.data = '{default: '0};
            out.keep = '0;
            out.last = 0;
        end
    endcase
end

endmodule
