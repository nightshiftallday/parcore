`timescale 1ns / 1ps

`include "libstf_macros.svh"

import lynxTypes::AXI_DATA_BITS;
import libstf::*;
import parcore::german_str_t;

/**
* Packs a stream of 16-byte German string views (one per handshake, terminated
* by `last`) into DATABEAT_SIZE-wide typed beats carrying STRINGS_PER_BEAT
* strings each.
*
* The output is tagged INT32_T: a 16-byte German string is stored in / looked
* up from the (unmodified) TypedDictionary as four raw 32-bit slots, with an
* IndexExpander turning each German-string index into the int32 indices
* 4*i .. 4*i+3. The 32-bit id path does no internal doubling, so one beat of 16
* slot indices reads back exactly one beat (4 german strings).
*
* Up to STRINGS_PER_BEAT-1 strings are buffered; the string that completes a
* beat (or carries `last`) is merged combinationally, so a full beat costs no
* extra latency.
*/
module GermanStrToTypedNData #(
    parameter int DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    data_i.s        in,   // #(german_str_t)
    typed_ndata_i.m out   // #(DATABEAT_SIZE), typ = INT32_T
);

localparam int GERMAN_BYTES     = $bits(german_str_t) / 8;
localparam int STRINGS_PER_BEAT = DATABEAT_SIZE / GERMAN_BYTES;
localparam int COUNT_BITS       = $clog2(STRINGS_PER_BEAT);

`ASSERT_ELAB(DATABEAT_SIZE % GERMAN_BYTES == 0)

german_str_t [STRINGS_PER_BEAT-1:0] acc;  // buffered strings (slots 0..count-1)
logic [COUNT_BITS-1:0]              count; // number currently buffered

// Emit when this incoming string fills the beat, or it is the final string.
logic emitting;
generate
if (STRINGS_PER_BEAT > 1)
    assign emitting = in.valid && ((count == COUNT_BITS'(STRINGS_PER_BEAT-1)) || in.last);
else
    assign emitting = in.valid;
endgenerate

assign in.ready  = emitting ? out.ready : 1'b1; // buffer freely until we must emit
assign out.valid = emitting;
assign out.typ   = INT32_T;
assign out.last  = in.last;

// Assemble the beat: buffered strings followed by the incoming string at slot
// `count`; higher slots are unused.
german_str_t [STRINGS_PER_BEAT-1:0] slot_data;
always_comb begin
    for (int s = 0; s < STRINGS_PER_BEAT; s++) begin
        if (s < count)       slot_data[s] = acc[s];
        else if (s == count) slot_data[s] = in.data;
        else                 slot_data[s] = '0;
    end
end

for (genvar s = 0; s < STRINGS_PER_BEAT; s++) begin
    for (genvar b = 0; b < GERMAN_BYTES; b++) begin
        assign out.data[s*GERMAN_BYTES + b] = slot_data[s][b*8 +: 8];
        assign out.keep[s*GERMAN_BYTES + b] = (s <= count); // slots 0..count valid
    end
end

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        count <= '0;
    end else if (in.valid && in.ready) begin
        count <= emitting ? '0 : (count + 1'b1);
    end
end

always_ff @(posedge clk) begin
    // Only buffer when we are not emitting (slot `count` < STRINGS_PER_BEAT-1).
    if (in.valid && in.ready && !emitting) begin
        acc[count] <= in.data;
    end
end

endmodule
