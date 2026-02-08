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

module PageDecoderConfig #(
    parameter NUM_STREAMS
) (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    page_decoder_config_i.m out[NUM_STREAMS]
);

localparam MAX_NUM_ENQUEUED_BUFFERS = 64;

`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
logic[AXIL_DATA_BITS - 1:0] values[2];
assign values[0] = PAGE_DECODER_CONFIG_ID;
assign values[1] = NUM_STREAMS

ConfigReadRegisterFile #(
    .NUM_REGS(2)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Write ----------------------------------------------------------------------------------------
for (genvar I = 0; I < NUM_STREAMS; I++) begin
    ready_valid_i #(compression_t) compression ();
    ConfigWriteFIFO #(I*4+0, MAX_NUM_ENQUEUED_BUFFERS, compression_t) inst_compression (clk, reset_synced, write_config, compression);

    ready_valid_i #(page_type_t) page_type ();
    ConfigWriteFIFO #(I*4+1, MAX_NUM_ENQUEUED_BUFFERS, page_type_t) inst_page_type (clk, reset_synced, write_config, page_type);

    ready_valid_i #(data32_t) num_values ();
    ConfigWriteFIFO #(I*4+2, MAX_NUM_ENQUEUED_BUFFERS, data32_t) inst_num_values (clk, reset_synced, write_config, num_values);

    ready_valid_i #(type_t) typ ();
    ConfigWriteFIFO #(I*4+3, MAX_NUM_ENQUEUED_BUFFERS, type_t) inst_typ (clk, reset_synced, write_config, typ);

    assign out[I].compression = compression.data;
    assign out[I].page_type = page_type.data;
    assign out[I].num_values = num_values.data;
    assign out[I].typ = typ.data;
    assign out[I].valid = compression.valid && page_type.valid && num_values.valid && typ.valid;

    assign compression.ready = page_type.valid && num_values.valid && typ.valid && out[I].ready;
    assign page_type.ready = compression.valid && num_values.valid && typ.valid && out[I].ready;
    assign num_values.ready = compression.valid && page_type.valid && typ.valid && out[I].ready;
    assign typ.ready = compression.valid && page_type.valid && num_values.valid && out[I].ready;
end

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
