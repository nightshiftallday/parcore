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
logic[VARINT_NUM_BYTES - 1:0] read_next_byte;
 
generate
    assign read_next_byte[0] = in_data[0][7];
    // The value out of the first byte should always be taken.
    assign value[6:0] = ({VARINT_NUM_BITS{1'b0}} | in_data[0][6:0]);

    for (genvar I = 1; I < VARINT_NUM_BYTES; I++) begin
        assign read_next_byte[I] = in_data[I][7] && read_next_byte[I-1];
    end

    for (genvar I = 1; I < VARINT_NUM_BYTES; I++) begin
        // We only take this byte if we're considering the i-th byte and the
        // (i-1)-th byte had the MSB to 1.
        assign value[(I+1) * 7 - 1:I * 7] = read_next_byte[I-1] ? in_data[I][6:0] : '0;
    end
endgenerate

assign out.valid = in.valid && ~read_next_byte[VARINT_NUM_BYTES - 1];
varint_t out_data;
assign out_data.value = value;
assign out_data.length = VARINT_LENGTH_BITS'($countones(read_next_byte) + 1);
assign out.data = out_data;

endmodule
