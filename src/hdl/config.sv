`timescale 1ns / 1ps

import libstf::*;
import parcore::compression_t;
import parcore::page_type_t;
import parcore::PARCORE_SYSTEM_ID;
import parcore::PAGE_DECODER_CONFIG_NUM_REGS;
import parcore::PAGE_DECODER_CONFIG_ID;
import parcore::HYBRID_PAGE_DECODER_CONFIG_NUM_REGS;
import parcore::HYBRID_PAGE_DECODER_CONFIG_ID;

`include "libstf_macros.svh"
`include "config_macros.svh"

module PageDecoderConfig (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    page_decoder_config_i.m out
);

`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
logic[AXIL_DATA_BITS - 1:0] values[PAGE_DECODER_CONFIG_NUM_REGS];
assign values[0] = PAGE_DECODER_CONFIG_ID;
generate
for (genvar I = 1; I < PAGE_DECODER_CONFIG_NUM_REGS; I++) begin
    assign values[I] = '0;
end
endgenerate

ConfigReadRegisterFile #(
    .NUM_REGS(PAGE_DECODER_CONFIG_NUM_REGS)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Write ----------------------------------------------------------------------------------------
ready_valid_i #(compression_t) compression ();
ConfigWriteFIFO #(0, 16, compression_t) inst_compression (clk, reset_synced, write_config, compression);

ready_valid_i #(page_type_t) page_type ();
ConfigWriteFIFO #(1, 16, page_type_t) inst_page_type (clk, reset_synced, write_config, page_type);

ready_valid_i #(data32_t) num_values ();
ConfigWriteFIFO #(2, 16, data32_t) inst_num_values (clk, reset_synced, write_config, num_values);

ready_valid_i #(type_t) typ ();
ConfigWriteFIFO #(3, 16, type_t) inst_typ (clk, reset_synced, write_config, typ);

assign out.compression = compression.data;
assign out.page_type = page_type.data;
assign out.num_values = num_values.data;
assign out.typ = typ.data;
assign out.valid = compression.valid && page_type.valid && num_values.valid && typ.valid;

assign compression.ready = page_type.valid && num_values.valid && typ.valid && out.ready;
assign page_type.ready = compression.valid && num_values.valid && typ.valid && out.ready;
assign num_values.ready = compression.valid && page_type.valid && typ.valid && out.ready;
assign typ.ready = compression.valid && page_type.valid && num_values.valid && out.ready;

endmodule

module HybridPageDecoderConfig (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    hybrid_page_decoder_config_i.m out
);

`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
data64_t values[HYBRID_PAGE_DECODER_CONFIG_NUM_REGS];
assign values[0] = HYBRID_PAGE_DECODER_CONFIG_ID;

ConfigReadRegisterFile #(
    .NUM_REGS(HYBRID_PAGE_DECODER_CONFIG_NUM_REGS)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Write ----------------------------------------------------------------------------------------
ready_valid_i #(data32_t) num_values ();
ConfigWriteFIFO #(0, 8, data32_t) inst_num_values (clk, reset_synced, write_config, num_values);

assign out.num_values = num_values.data;
assign out.valid = num_values.valid;
assign num_values.ready = out.ready;

endmodule
