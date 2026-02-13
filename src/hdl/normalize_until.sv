`timescale 1ns / 1ps

`include "libstf_macros.svh"

import lynxTypes::*;
import libstf::data8_t;

// Normalized the data in a continguous stream until a number of values have
// been collected. That is specified with the `size` input. This module can be
// configured through `size` only after the previous transfer has finished.
module NormalizeUntil #(
    type data_t,
    type size_t,
    parameter NUM_ELEMENTS = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s size, // #(size_t)

    ndata_i.s in,         // #(data_t, NUM_ELEMENTS)
    ndata_i.m out         // #(data_t, NUM_ELEMENTS)
);

`RESET_RESYNC // Reset pipelining

size_t remaining;

logic unconfigured;
assign unconfigured = remaining == 0;

assign size.ready = unconfigured;

ndata_i #(data_t, NUM_ELEMENTS) in_inner (), normalizer_in (), out_inner ();

// This is on purpose 1 bit wider to account for the case where keep is 0xf..f
logic [$clog2(NUM_ELEMENTS):0] in_num_values;
assign in_num_values = $countones(in_inner.keep);
size_t next_remaining;
assign next_remaining = remaining - in_num_values;

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        remaining <= '0;
    end else begin
        if (unconfigured) begin
            if (size.valid) begin
                remaining <= size.data;
            end
        end else begin
            if (in_inner.ready && in_inner.valid) begin
                remaining <= next_remaining;
            end
        end
    end
end

NDataSkidBuffer #(data_t, NUM_ELEMENTS) inst_in_skid_buffer  (
    .clk(clk),
    .rst_n(reset_synced),

    .in(in),
    .out(in_inner)
);

DataNormalizer #(
    .data_t(data_t),
    .NUM_ELEMENTS(NUM_ELEMENTS),
    .ENABLE_COMPACTOR(0)
) inst_data_normalizer (
    .clk(clk),
    .rst_n(reset_synced),

    .in(normalizer_in),
    .out(out_inner)
);

NDataSkidBuffer #(data_t, NUM_ELEMENTS) inst_out_skid_buffer (
    .clk(clk),
    .rst_n(reset_synced),

    .in(out_inner),
    .out(out)
);

assign in_inner.ready = normalizer_in.ready && ~unconfigured;
assign normalizer_in.valid = in_inner.valid && ~unconfigured;
assign normalizer_in.data = in_inner.data;
assign normalizer_in.keep = in_inner.keep;
assign normalizer_in.last = in_inner.last && next_remaining == 0;

endmodule

module TypedNormalizeUntil #(
    type size_t,
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s size, // #(size_t)

    typed_ndata_i.s in,         // #(DATABEAT_SIZE)
    typed_ndata_i.m out         // #(DATABEAT_SIZE)
);

valid_i #(type_t) keep_typ ();
type_t typ;
assign typ = keep_typ.valid ? keep_typ.data : in.typ;

ndata_i #(data8_t, DATABEAT_SIZE) in_inner (), out_inner ();

`DATA_ASSIGN(in, in_inner);

NormalizeUntil #(data8_t, size_t, DATABEAT_SIZE) inst_normalize_until (
    .clk(clk),
    .rst_n(rst_n),

    .size(size),

    .in(in_inner),
    .out(out_inner)
);

`DATA_ASSIGN(out_inner, out);
assign out.typ = typ;

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        keep_typ.valid <= 1'b0;
    end else begin
        if (~keep_typ.valid && in.valid) begin
            keep_typ.data <= in.typ;
            keep_typ.valid <= 1'b1;
        end

        if (out.ready && out.valid && out.last) begin
            keep_typ.valid <= 1'b0;
        end
    end
end

endmodule
