`timescale 1ns / 1ps

import libstf::*;
import parcore::*;

`include "libstf_macros.svh"
`include "config_macros.svh"

module ColumnChunkDecoderConfig #(
    parameter NUM_DECODERS
) (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    column_chunk_decoder_config_i.m out[NUM_DECODERS]
);

localparam MAX_NUM_ENQUEUED_BUFFERS = 64;
localparam NUM_WRITE_REGS = COLUMN_CHUNK_DECODER_CONFIG_REGS;

`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
logic[AXIL_DATA_BITS - 1:0] values[2];
assign values[0] = COLUMN_CHUNK_DECODER_CONFIG_ID;
assign values[1] = NUM_DECODERS;

ConfigReadRegisterFile #(
    .NUM_REGS(2)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Write ----------------------------------------------------------------------------------------
for (genvar I = 0; I < NUM_DECODERS; I++) begin
    ready_valid_i #(compression_t) compression(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+0, MAX_NUM_ENQUEUED_BUFFERS, compression_t) inst_compression (clk, reset_synced, write_config, compression);

    ready_valid_i #(data32_t) num_values(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+1, MAX_NUM_ENQUEUED_BUFFERS, data32_t) inst_num_values (clk, reset_synced, write_config, num_values);

    ready_valid_i #(data32_t) hybrid_num_values(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+2, MAX_NUM_ENQUEUED_BUFFERS, data32_t) inst_hybrid_num_values (clk, reset_synced, write_config, hybrid_num_values);

    ready_valid_i #(type_t) typ(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+3, MAX_NUM_ENQUEUED_BUFFERS, type_t) inst_typ (clk, reset_synced, write_config, typ);

    assign out[I].compression = compression.data;
    assign out[I].num_values = num_values.data;
    assign out[I].hybrid_num_values = hybrid_num_values.data;
    assign out[I].typ = typ.data;
    assign out[I].valid = compression.valid && num_values.valid && hybrid_num_values.valid && typ.valid;

    assign compression.ready = num_values.valid && hybrid_num_values.valid && typ.valid && out[I].ready;
    assign num_values.ready = compression.valid && hybrid_num_values.valid && typ.valid && out[I].ready;
    assign hybrid_num_values.ready = compression.valid && num_values.valid && typ.valid && out[I].ready;
    assign typ.ready = compression.valid && num_values.valid && hybrid_num_values.valid && out[I].ready;
end

endmodule

module PageDecoderConfig #(
    parameter NUM_DECODERS
) (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    page_decoder_config_i.m out[NUM_DECODERS]
);

localparam MAX_NUM_ENQUEUED_BUFFERS = 64;
localparam NUM_WRITE_REGS = PAGE_DECODER_CONFIG_REGS;

`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
logic[AXIL_DATA_BITS - 1:0] values[2];
assign values[0] = PAGE_DECODER_CONFIG_ID;
assign values[1] = NUM_DECODERS;

ConfigReadRegisterFile #(
    .NUM_REGS(2)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Write ----------------------------------------------------------------------------------------
for (genvar I = 0; I < NUM_DECODERS; I++) begin
    ready_valid_i #(page_type_t) page_type(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+0, MAX_NUM_ENQUEUED_BUFFERS, page_type_t) inst_page_type (clk, reset_synced, write_config, page_type);

    ready_valid_i #(data32_t) num_values(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+1, MAX_NUM_ENQUEUED_BUFFERS, data32_t) inst_num_values (clk, reset_synced, write_config, num_values);

    ready_valid_i #(logic) last(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+2, MAX_NUM_ENQUEUED_BUFFERS, type_t) inst_last (clk, reset_synced, write_config, last);

    assign out[I].page_type = page_type.data;
    assign out[I].num_values = num_values.data;
    assign out[I].last = last.data;
    assign out[I].valid = page_type.valid && num_values.valid && last.valid;

    assign page_type.ready = num_values.valid && last.valid && out[I].ready;
    assign num_values.ready = page_type.valid && last.valid && out[I].ready;
    assign last.ready = page_type.valid && num_values.valid && out[I].ready;
end

endmodule
