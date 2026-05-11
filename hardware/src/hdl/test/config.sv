`timescale 1ns / 1ps

import libstf::*;
import parcore::*;
import parcore_test::*;

`include "libstf_macros.svh"
`include "config_macros.svh"

module HybridPageDecoderConfig (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    ready_valid_i.m out // #(data32_t)
);


`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
data64_t values[1];
assign values[0] = HYBRID_PAGE_DECODER_CONFIG_ID;

ConfigReadRegisterFile #(
    .NUM_REGS(1)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Write ----------------------------------------------------------------------------------------
ConfigWriteFIFO #(0, 8, data32_t) inst_num_values (clk, reset_synced, write_config, out);

endmodule

module RunDecoderConfig (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    ready_valid_i.m out // #(run_decoder_config_t)
);

localparam longint unsigned RUN_DECODER_CONFIG_ID = 64'hd6736a190f91fa01;

`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
data64_t values[1];
assign values[0] = RUN_DECODER_CONFIG_ID;

ConfigReadRegisterFile #(
    .NUM_REGS(1)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Write ----------------------------------------------------------------------------------------
ready_valid_i #(bit_width_t) bit_width ();
ConfigWriteFIFO #(0, 8, bit_width_t) inst_bit_width (clk, reset_synced, write_config, bit_width);

ready_valid_i #(offset_t) offset ();
ConfigWriteFIFO #(0, 8, offset_t) inst_offset (clk, reset_synced, write_config, offset);

ready_valid_i #(data32_t) num_values ();
ConfigWriteFIFO #(0, 8, data32_t) inst_num_values (clk, reset_synced, write_config, num_values);

bpe_config_t data;
assign data.bit_width = bit_width.data;
assign data.offset = offset.data;
assign data.num_values = num_values.data;

assign out.data = data;
assign out.valid = bit_width.valid && offset.valid && num_values.data;

assign bit_width.ready = offset.ready && num_values.ready && out.ready;
assign offset.ready = bit_width.ready && num_values.ready && out.ready;
assign num_values.ready = bit_width.ready && offset.ready && out.ready;

endmodule
