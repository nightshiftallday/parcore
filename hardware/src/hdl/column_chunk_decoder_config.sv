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

    ready_valid_i.m out[NUM_DECODERS], // #(column_chunk_conf_t)

    input decoder_profile_t profile[NUM_DECODERS]
);

localparam MAX_NUM_ENQUEUED_BUFFERS = 64;
localparam NUM_WRITE_REGS = COLUMN_CHUNK_DECODER_CONFIG_REGS;

// Info registers followed by the per-decoder profiling counters. Each decoder
// contributes 8 counters (4 input + 4 output stream profile counters).
localparam NUM_INFO_REGS    = COLUMN_CHUNK_DECODER_INFO_REGS;
localparam NUM_PROFILE_REGS = COLUMN_CHUNK_DECODER_PROFILE_REGS;
localparam NUM_READ_REGS    = COLUMN_CHUNK_DECODER_READ_REGS(NUM_DECODERS);

`RESET_RESYNC // Reset pipelining

// -- Read -----------------------------------------------------------------------------------------
logic[AXIL_DATA_BITS - 1:0] values[NUM_READ_REGS];
assign values[0] = COLUMN_CHUNK_DECODER_CONFIG_ID;
assign values[1] = NUM_DECODERS;
assign values[2] = MAX_NUM_ENQUEUED_BUFFERS;

for (genvar I = 0; I < NUM_DECODERS; I++) begin
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 0] = profile[I].in.handshakes_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 1] = profile[I].in.starved_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 2] = profile[I].in.stalled_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 3] = profile[I].in.idle_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 4] = profile[I].out.handshakes_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 5] = profile[I].out.starved_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 6] = profile[I].out.stalled_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 7] = profile[I].out.idle_cycles;
end

ConfigReadRegisterFile #(
    .NUM_REGS(NUM_READ_REGS)
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

    ready_valid_i #(type_t) typ(clk, reset_synced);
    ConfigWriteFIFO #(I*NUM_WRITE_REGS+2, MAX_NUM_ENQUEUED_BUFFERS, type_t) inst_typ (clk, reset_synced, write_config, typ);

    assign out[I].data.compression       = compression.data;
    assign out[I].data.num_values        = num_values.data;
    assign out[I].data.typ               = typ.data;
    assign out[I].valid = compression.valid && num_values.valid && typ.valid;

    assign compression.ready       = num_values.valid && typ.valid && out[I].ready;
    assign num_values.ready        = compression.valid && typ.valid && out[I].ready;
    assign typ.ready               = compression.valid && num_values.valid && out[I].ready;
end

endmodule
