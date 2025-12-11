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

localparam int MAX_IN_TRANSIT = 8;
localparam int DATA_SIZE = ($bits(data_t) + 7) / 8;
localparam int VARINT_OFFSET_COMPUTATION_WIDTH = 18;

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
    ST_DECODE_BPE
} state_t;
state_t state;
logic store_in_second_half;

data8_t[NUM_BYTES * 2 - 1:0] keep_data;
logic[NUM_BYTES * 2 - 1:0] keep_keep;
logic keep_last_received;
bit_width_t bit_width;
logic [BPE_MASK_SIZE - 1:0] bit_width_bpe_mask;
offset_t offset;
data32_t remaining_values;

// n bits for bit_width_t, + log2(NUM_ELEMENTS) bits
// as this value is the result of bit_width * NUM_ELEMENTS;
logic[$clog2(NUM_ELEMENTS) + $bits(bit_width_t) - 1:0] packed_databeat_bits;
offset_t varint_offset;

// ------- Output declaration -----
typedef enum logic {
  OUTPUT_RLE,
  OUTPUT_BPE
} output_t;
valid_i #(output_t) next_out (), curr_out ();

always_comb begin
    next_out.valid = 0;

    case (state)
        ST_DECODE_RLE: begin
            next_out.data = OUTPUT_RLE;
            next_out.valid = rle_in.valid && rle_in.ready;
        end

        ST_DECODE_BPE: begin
            next_out.data = OUTPUT_BPE;
            next_out.valid = bpe_in.valid && bpe_in.ready;
        end
    endcase
end

// ------- State declaration (decoders) -----
logic [3:0] rle_width;
rle_count_t rle_count;

typedef logic [VARINT_OFFSET_COMPUTATION_WIDTH - $bits(offset_t):0] bpe_remaining_inputs_t;

// The value in bpe_count is computed by << 3 the value in the header
// (ignoring the LSB). This means that it'll be a multiple of 8.
// For runs where the number of values encoded in BPE is not a multiple of 8,
// the bpe_count is lower-bounded by the total number of values in the page,
// which is found in in_meta_data.num_values.
bpe_count_t bpe_count;
bpe_remaining_inputs_t bpe_remaining_inputs; 

// bpe_offset is the number of offset bits to add on top of the byte offset
// global to the decoder.
typedef logic[$clog2(NUM_ELEMENTS) * $bits(bit_width_t) - 1:0] bpe_offset_t;
bpe_offset_t bpe_offset;


// ------- Combinatorial state (decoders) ---
// This is a bit-level view of the data
logic [NUM_BYTES * 8 * 2 - 1:0] bpe_data;
generate
for (genvar i = 0; i < NUM_BYTES * 2; i++) begin
    assign bpe_data[(i+1) * 8 - 1:i * 8] = keep_data[i];
end
endgenerate

// ------- Header varint decoding

// To have some valid varint input, we must either have:
// - up to 4 valid bytes
// - at least 1 valid byte if we've received last. We assume the input is
// correct.
valid_i #(data8_t[VARINT_NUM_BYTES - 1:0]) varint_in ();
valid_i #(varint_t) varint_out ();

VarintDecoder inst_varint_decoder (
    .in(varint_in),
    .out(varint_out)
);

// assert property (@(posedge clk) disable iff (!rst_n) !varint_in.valid || (keep_data[varint_offset +: 4] == varint_in.data))
// else $fatal(1, "Varint input data does not match the data at the current offset. In state %d, at varint_offset 0x%x, offset 0x%x, expected 0b%b (%d), got 0b%b (%d)", state, varint_offset, offset, keep_data[varint_offset +: 4], keep_data[varint_offset +: 4], varint_in.data, varint_in.data);

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

ExpandRLE #(
    .data_t(data_t),
    .NUM_ELEMENTS(NUM_ELEMENTS)
) inst_expand_rle (
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
        assign rle_in.data[i * 8 + b] = (i < rle_width) ? keep_data[offset+i][b] : '0;
    end
    assign rle_in_valid_bits[i] = (i >= rle_width) || keep_keep[offset+i];
    assign rle_needs_to_buffer_bits[i] = (i < rle_width && ~keep_keep[offset+i]);
end
endgenerate
assign rle_in.valid = &rle_in_valid_bits && state == ST_DECODE_RLE;
logic rle_needs_more_input;
assign rle_needs_more_input = |rle_needs_to_buffer_bits && ~keep_last_received;

// ------- BPE decoding
bpe_metadata_t bpe_in_tag;
assign bpe_in_tag.bit_width = bit_width;
assign bpe_in_tag.mask = bit_width_bpe_mask;
assign bpe_in_tag.count = bpe_count;

tagged_i #(logic [$bits(data_t) * NUM_ELEMENTS - 1:0], $bits(bpe_metadata_t)) bpe_in ();
ndata_i #(data_t, NUM_ELEMENTS) bpe_out ();

ExpandBPE #(
    .data_t(data_t),
    .NUM_ELEMENTS(NUM_ELEMENTS),
    .MAX_IN_TRANSIT(MAX_IN_TRANSIT)
) inst_expand_bpe (
    .clk(clk),
    .rst_n(rst_n),

    .in(bpe_in),
    .out(bpe_out)
);

// NOTE: ExpandBPE doesn't look at the keep signals.
assign bpe_in.data = bpe_data[offset * 8 + bpe_offset +: $bits(data_t) * NUM_ELEMENTS];
assign bpe_in.last = bpe_count <= NUM_ELEMENTS;
assign bpe_in.tag = bpe_in_tag;
// OPTIMIZATION: here we're only checking for the first and last bit of the
// desired keep region, to avoid a wide | over several bits.
logic bpe_valid_bytes;
assign bpe_valid_bytes = keep_keep[offset] && keep_keep[offset + packed_databeat_bits / 8 - 1];

assign bpe_in.valid = state == ST_DECODE_BPE && (bpe_valid_bytes || keep_last_received) && bpe_count > 0;

// We want to take more input if some of the keep_keep bytes are not high, and
// only if we haven't already consumed the last databeat.
logic bpe_needs_more_input;
assign bpe_needs_more_input = ~bpe_valid_bytes && ~keep_last_received;

// ------- State machine ---------
function offset_t trim_offset(offset_t offset);
    trim_offset = offset >= NUM_BYTES ? offset - NUM_BYTES : offset;
endfunction

task store_input(input data8_t[NUM_BYTES - 1:0] data,
                 input logic[NUM_BYTES - 1:0] keep,
                 input logic last);
    if (store_in_second_half) begin
        keep_data[NUM_BYTES * 2 - 1:NUM_BYTES] <= data;
        keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES] <= keep;
    end else begin
        keep_data[NUM_BYTES - 1:0] <= data;
        keep_keep[NUM_BYTES - 1:0] <= keep;
    end

    keep_last_received <= last;
    store_in_second_half <= ~store_in_second_half;
endtask

task update_offset(input offset_t next_offset, input offset_t trimmed_offset);
    // If the new offset is beyond the midpoint of the keep_data buffer, which
    // holds two databeats, then we rewrite the offset and move the second
    // half of the buffer into the first, zeroing the second.
    if (next_offset >= NUM_BYTES) begin
        keep_data[NUM_BYTES - 1:0] <= keep_data[NUM_BYTES * 2 - 1:NUM_BYTES];
        keep_keep[NUM_BYTES - 1:0] <= keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES];

        keep_data[NUM_BYTES * 2 - 1:NUM_BYTES] <=  '{default: 'x};
        keep_keep[NUM_BYTES * 2 - 1:NUM_BYTES] <=  '0;

        store_in_second_half <= ~store_in_second_half;
    end
    offset <= trimmed_offset;
endtask

task reset();
    state <= ST_IDLE;
    keep_data <= 'x;
    keep_keep <= '0;
    keep_last_received <= '0;
    store_in_second_half <= 0;

    bit_width <= '0;
    bit_width_bpe_mask <= '0;
    packed_databeat_bits <= '0;
    rle_width <= '0;
    varint_offset <= '0;
    varint_in.valid <= 0;
    offset <= '0;
    remaining_values <= '0;
endtask

task goto_decode(input data32_t remaining_values);
    logic less_remaining_values_than_next_bpe_count;
    offset_t next_offset;
    bpe_count_t next_bpe_count, next_bpe_padded_count;

    less_remaining_values_than_next_bpe_count = remaining_values < varint_no_encoding_bytes;
    next_offset = trim_offset(run_data_offset);
    next_bpe_count = less_remaining_values_than_next_bpe_count ? remaining_values : varint_no_encoding_bytes;
    next_bpe_padded_count = varint_no_encoding_bytes;

    `ifndef SYNTHESIS
    if (~varint_out.valid) begin
        $fatal(1, "Called goto_decode() when varint_out.valid = %b", varint_out.valid);
    end
    `endif

    update_offset(run_data_offset, next_offset);
    if (varint_encoding == ENCODING_BPE) begin
        state <= ST_DECODE_BPE;

        // Compute BPE properties
        bpe_offset <= 0;
        bpe_count <= next_bpe_count;

        goto_decode_bpe(bpe_offset, next_bpe_padded_count, next_offset);
    end else begin
        // Compute RLE properties
        rle_count <= varint_no_encoding;

        goto_decode_rle(next_offset);
    end
endtask

task goto_decode_bpe(
    input bpe_offset_t bpe_offst,
    input bpe_count_t bpe_padded_cnt,
    input offset_t offst
);
    logic [VARINT_OFFSET_COMPUTATION_WIDTH - 1:0] next_varint_offset; 
    offset_t next_varint_offset;
    bpe_remaining_inputs_t next_bpe_remaining_inputs; 

    next_varint_offset = offst + (bpe_padded_cnt * bit_width) / 8;
    next_bpe_remaining_inputs = bpe_padded_cnt / NUM_ELEMENTS;

    // BPE could contain so many values that the offset would go beyond two
    // databeats, in that case, we set the varint position but we don't make
    // it valid
    // invalid valid signals computed with the trimmed offset (short_offset).
    varint_offset <= next_varint_offset[$bits(offset_t) - 2:0];
    bpe_remaining_inputs <= next_bpe_remaining_inputs;
    if (next_bpe_remaining_inputs <= 1) begin
        // Here we use next_varint_offset (which may be > NUM_BYTES) as if
        // that's the case, in this databeat we also moved the offset forward
        // and shifted the keep_data, so we store the varint_offset trimmed
        // (outside of this loop) but compute the correct varint_in data to
        // match.
        update_varint_data(keep_data, next_varint_offset);
        update_varint_valid(keep_keep, keep_last_received, next_varint_offset);
    end else begin
        varint_in.valid <= 0;
    end

    state <= ST_DECODE_BPE;
endtask

task advance_bpe();
    logic[$clog2(NUM_ELEMENTS) + $bits(bit_width_t):0] next_bpe_offset_bits;
    bpe_count_t next_bpe_count;
    bpe_offset_t next_bpe_offset;
    bpe_remaining_inputs_t  next_bpe_remaining_inputs;
    offset_t next_offset;

    // TODO: can't we remove these checks for min(..., 0) given that here
    // we know we're not on the last databeat for BPE so these values should
    // not go below zero
    next_bpe_offset_bits = bpe_offset + packed_databeat_bits;
    next_bpe_count = bpe_count - NUM_ELEMENTS;
    next_bpe_offset = next_bpe_offset_bits % 8;
    next_bpe_remaining_inputs = bpe_remaining_inputs - 1;
    next_offset = offset + (next_bpe_offset_bits / 8);

    bpe_count <= next_bpe_count;
    bpe_offset <= next_bpe_offset;
    remaining_values <= remaining_values - NUM_ELEMENTS;
    bpe_remaining_inputs <= next_bpe_remaining_inputs;
    update_offset(next_offset, trim_offset(next_offset));

    if (next_bpe_remaining_inputs <= 1) begin
        offset_t actual_varint_offset;
        actual_varint_offset = next_offset >= NUM_BYTES ? NUM_BYTES + varint_offset : varint_offset;

        update_varint_data(keep_data, actual_varint_offset);
        update_varint_valid(keep_keep, keep_last_received, actual_varint_offset);
    end
endtask

task finish_bpe();
    data32_t next_remaining_values;
    next_remaining_values = remaining_values - bpe_count;

    remaining_values <= next_remaining_values;
    if (next_remaining_values == 0) begin
        reset();
    end else if (varint_out.valid) begin
        // If the varint for the next databeat is already valid and parsed, we can
        // move forward to the next decode, otherwise we store the varint offset
        // which we're trying to decode and move to a state waiting for more input).
        goto_decode(next_remaining_values);
    end else begin
        update_varint_data(keep_data, varint_offset);
        update_varint_valid(keep_keep, keep_last_received, varint_offset);
        // If ~varint_out.valid we need to fetch more input to
        // satisfy it.
        state <= ST_HEADER2;
    end
endtask

task goto_decode_rle(input offset_t offst);
    state <= ST_DECODE_RLE;
    varint_offset <= offst + rle_width;
    update_varint_data(keep_data, offst + rle_width);
    update_varint_valid(keep_keep, keep_last_received, offst + rle_width);
endtask

task finish_rle();
    data32_t next_remaining_values;
    next_remaining_values = remaining_values - rle_count;

    remaining_values <= next_remaining_values;
    if (next_remaining_values == 0) begin
        reset();
    end else if (varint_out.valid) begin
        // If the varint for the next databeat is already valid and parsed, we can
        // move forward to the next decode, otherwise we store the varint offset
        // which we're trying to decode and move to a state waiting for more input).
        goto_decode(next_remaining_values);
    end else begin
        // If ~varint_out.valid we need to fetch more input to
        // satisfy it.
        state <= ST_HEADER2;
    end
endtask

task update_varint_data(input data8_t[NUM_BYTES * 2 - 1:0] data, offset_t offst);
    varint_in.data <= data[offst +: 4];
endtask

task update_varint_valid(input logic[NUM_BYTES * 2 - 1:0] keep, logic last_received, offset_t offst);
    varint_in.valid <= keep[offst] && (last_received || (&keep[(offst + 1) +: 3]));
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        reset();
    end else begin
        if (in.ready && in.valid) begin
            store_input(in_data, in_keep, in.last);
        end

        case (state)
            ST_IDLE: begin
                if (in_meta.ready && in_meta.valid) begin
                    bit_width <= in_meta_data.bit_width;
                    bit_width_bpe_mask <= BPE_MASK_SIZE'((1 << in_meta_data.bit_width) - 1);
                    packed_databeat_bits <= NUM_ELEMENTS * in_meta_data.bit_width;
                    rle_width <= (in_meta_data.bit_width + 7) >> 3;
                    offset <= in_meta_data.offset;
                    varint_offset <= in_meta_data.offset;
                    remaining_values <= in_meta_data.num_values;
                    
                    if (in.valid) begin
                        state <= ST_HEADER2;
                        update_varint_data(in.data, in_meta_data.offset);
                        update_varint_valid(in.keep, in.last, in_meta_data.offset);
                    end else begin
                        state <= ST_HEADER;
                    end
                end
            end

            // Here we have received the configuration but we haven't yet
            // received the input. Receiving one databeat may or may not be
            // enough.
            ST_HEADER: begin
                if (in.valid) begin
                    update_varint_data(in.data, varint_offset);
                    update_varint_valid(in.keep, in.last, varint_offset);
                    // If we receive input, the varint decoding is not yet done
                    // as it takes one cycle. Move to the next state so that
                    // we can optionally take even more input if needed for
                    // the varint decoding.
                    state <= ST_HEADER2;
                end
            end

            // Here we have received the configuration and one input databeat,
            // but we weren't able to decode the header varint with just that.
            ST_HEADER2: begin
                if (varint_out.valid) begin
                    goto_decode(remaining_values);
                end else if (in.valid) begin
                    update_varint_data(in.data, varint_offset);
                    update_varint_valid(in.keep, in.last, varint_offset);
                end
            end

            ST_DECODE_RLE: begin
                if (rle_in.ready && rle_in.valid) begin
                    finish_rle();
                end
            end

            ST_DECODE_BPE: begin
                if (bpe_in.ready && bpe_in.valid) begin
                    if (bpe_in.last) begin
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
always_comb begin
    // We need to provide default values to prevent latch inference
    in_meta.ready = state == ST_IDLE; 

    in.ready = 0;
    case (state)
        ST_IDLE:
            in.ready = in_meta.valid;

        ST_HEADER, ST_HEADER2:
            in.ready = ~varint_in.valid;

        ST_DECODE_RLE:
            in.ready = rle_needs_more_input;
            
        ST_DECODE_BPE:
            in.ready = bpe_needs_more_input;
    endcase
end

// ------- Driving output --------

logic fifo_in_ready, fifo_out_ready;
FIFO #(
    .DEPTH(MAX_IN_TRANSIT*2),
    .WIDTH($bits(output_t))
) inst_output_fifo (
    .i_clk(clk),
    .i_rst_n(rst_n),

    .i_data(next_out.data),
    .i_valid(next_out.valid),
    .i_ready(fifo_in_ready),

    .o_data(curr_out.data),
    .o_valid(curr_out.valid),
    .o_ready(fifo_out_ready),

    .o_filling_level()
);

assert property (@(posedge clk) disable iff (!rst_n) fifo_in_ready || !next_out.valid)
else $fatal(1, "Output FIFO is not ready to take input but next_out is valid");

always_comb begin
    rle_out.ready = 0;
    bpe_out.ready = 0;
    out.valid = 0;
    out.data = '{default: 'x};
    out.keep = '0;
    out.last = 0;
    fifo_out_ready = 0;

    if (curr_out.valid) begin
        case (curr_out.data)
            OUTPUT_RLE: begin
              rle_out.ready = out.ready;
              out.valid = rle_out.valid;
              out.data = rle_out.data;
              out.keep = rle_out.keep;
              out.last = rle_out.last;
              fifo_out_ready = out.ready && out.valid && out.last;
            end

            OUTPUT_BPE: begin
              bpe_out.ready = out.ready;
              out.valid = bpe_out.valid;
              out.data = bpe_out.data;
              out.keep = bpe_out.keep;
              out.last = bpe_out.last;
              fifo_out_ready = out.ready && out.valid;
            end
        endcase
    end
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
