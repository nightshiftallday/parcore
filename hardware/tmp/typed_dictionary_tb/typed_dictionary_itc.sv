`timescale 1ns / 1ps

// TypedDictionary with the inline 32/64-bit ID doubling replaced by IndexTypeConverter. Ports,
// value path and output path are identical to typed_dictionary_inline.sv, so the two differ only
// in how the ids are converted before they reach the Dictionary.

import libstf::*;

module TypedDictionaryITC #(
    parameter type id_t,
    parameter DATABEAT_SIZE,
    parameter NUM_ELEMENTS = DATABEAT_SIZE / TYPED_DICTIONARY_DATA_SIZE,
    parameter NUM_BANKS = 16
) (
    input logic clk,
    input logic rst_n,

    typed_ndata_i.s in_values, // #(DATABEAT_SIZE)
    ndata_i.s in_ids,          // #(id_t, NUM_ELEMENTS)

    typed_ndata_i.m out        // #(DATABEAT_SIZE)
);

`ASSERT_ELAB(DATABEAT_SIZE == NUM_ELEMENTS * TYPED_DICTIONARY_DATA_SIZE)

valid_i #(type_t) typ(clk, rst_n);

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        typ.valid <= 0;
    end else if (in_values.ready && in_values.valid) begin
        typ.data <= in_values.typ;
        typ.valid <= 1;
    end
end

ndata_i #(typed_dictionary_data_t, NUM_ELEMENTS) dictionary_in_values(clk, rst_n);
ndata_i #(id_t,                    NUM_ELEMENTS) dictionary_in_ids(clk, rst_n);
ndata_i #(typed_dictionary_data_t, NUM_ELEMENTS) dictionary_out(clk, rst_n);

assign in_values.ready = dictionary_in_values.ready;
generate
for (genvar i = 0; i < NUM_ELEMENTS; i++) begin
    assign dictionary_in_values.data[i] = in_values.data[(i+1) * TYPED_DICTIONARY_DATA_SIZE - 1:i * TYPED_DICTIONARY_DATA_SIZE];
    assign dictionary_in_values.keep[i] = &in_values.keep[(i+1) * TYPED_DICTIONARY_DATA_SIZE - 1:i * TYPED_DICTIONARY_DATA_SIZE];
end
endgenerate
assign dictionary_in_values.last = in_values.last;
assign dictionary_in_values.valid = in_values.valid;

// -- ID conversion --------------------------------------------------------------------------------
typed_ndata_i #(NUM_ELEMENTS, id_t) typed_ids(clk, rst_n);
typed_ndata_i #(NUM_ELEMENTS, id_t) converted_ids(clk, rst_n);

// Ids are only accepted once a value stream has fixed the type, as in the inline version.
assign typed_ids.data  = in_ids.data;
assign typed_ids.typ   = typ.data;
assign typed_ids.keep  = in_ids.keep;
assign typed_ids.last  = in_ids.last;
assign typed_ids.valid = typ.valid && in_ids.valid;
assign in_ids.ready    = typ.valid && typed_ids.ready;

(* keep_hierarchy = "yes" *)
IndexTypeConverter #(
    .id_t         (id_t),
    .NUM_ELEMENTS (NUM_ELEMENTS),
    .BASE_TYPE    (INT32_T),
    .NUM_TYPES    (4),
    .TYPES        ('{INT32_T, FLOAT_T, INT64_T, DOUBLE_T})
) inst_index_type_converter (
    .clk   (clk),
    .rst_n (rst_n),
    .in    (typed_ids),
    .out   (converted_ids)
);

assign dictionary_in_ids.data  = converted_ids.data;
assign dictionary_in_ids.keep  = converted_ids.keep;
assign dictionary_in_ids.last  = converted_ids.last;
assign dictionary_in_ids.valid = converted_ids.valid;
assign converted_ids.ready     = dictionary_in_ids.ready;

// -- Assertions -----------------------------------------------------------------------------------
`ifndef SYNTHESIS
assert property (@(posedge clk) disable iff (!rst_n) !typ.valid || GET_TYPE_WIDTH(typ.data) == 32 || GET_TYPE_WIDTH(typ.data) == 64)
else $fatal(1, "Module TypedDictionaryITC only supports types that are either 32 or 64 bits, instead got %d bits", GET_TYPE_WIDTH(typ.data));
`endif

// Kept as a separate hierarchy so the synthesis reports separate the id conversion from it.
(* keep_hierarchy = "yes" *)
Dictionary #(
    .value_t(data32_t),
    .id_t(id_t),
    .NUM_ELEMENTS(NUM_ELEMENTS),
    .NUM_BANKS(NUM_BANKS)
) inst_dictionary (
    .clk(clk),
    .rst_n(rst_n),

    .in_values(dictionary_in_values),
    .in_ids(dictionary_in_ids),

    .out(dictionary_out)
);

assign dictionary_out.ready = typ.valid && out.ready;

generate
for (genvar i = 0; i < NUM_ELEMENTS; i++) begin
    assign out.data[(i+1) * TYPED_DICTIONARY_DATA_SIZE - 1:i * TYPED_DICTIONARY_DATA_SIZE] = dictionary_out.data[i];
    assign out.keep[(i+1) * TYPED_DICTIONARY_DATA_SIZE - 1:i * TYPED_DICTIONARY_DATA_SIZE] = {TYPED_DICTIONARY_DATA_SIZE{dictionary_out.keep[i]}};
end
endgenerate

assign out.typ = typ.data;
assign out.last = dictionary_out.last;
assign out.valid = typ.valid && dictionary_out.valid;

endmodule
