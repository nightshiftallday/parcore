`timescale 1ns / 1ps

`include "parcore_types.svh"
import parcore::*;
import libstf::data8_t;

module VarintDecoder (
  valid_i.s in,  // #(data8_t[VARINT_NUM_BYTES - 1:0])
  valid_i.m out // #(logic [VARINT_NUM_BYTES * 8 - 1:0])
);

data8_t[3:0] in_data;
assign in_data = in.data;

logic[VARINT_NUM_BITS - 1:0] value;
logic read_next_byte[VARINT_NUM_BYTES - 1:0];

always_comb begin
    for (int i = 0; i < VARINT_NUM_BYTES; i++) begin
        read_next_byte[i] = in_data[i][7];
        if (i > 0) begin
            read_next_byte[i] &= read_next_byte[i-1];
        end
    end

    value = '0;
    for (int i = 0; i < VARINT_NUM_BYTES; i++) begin
        // We only take this byte if:
        // - we're considering the first byte. That is always valid
        // - we're considering the i-th byte and the (i-1)-th byte had the MSB
        // to 1.
        if (i <= 0 || read_next_byte[i-1]) begin
            value |= ({VARINT_NUM_BITS{1'b0}} | in_data[i][6:0]) << (i * 7);
        end
    end
end

assign out.valid = in.valid && ~read_next_byte[VARINT_NUM_BYTES - 1];
varint_t out_data;
assign out_data.value = value;
assign out_data.length = $countones(read_next_byte) + 1;
assign out.data = out_data;

endmodule
