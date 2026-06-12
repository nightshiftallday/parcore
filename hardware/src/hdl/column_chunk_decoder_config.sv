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
    ConfigWriteFIFO #(I, MAX_NUM_ENQUEUED_BUFFERS, column_chunk_conf_t) inst_conf (clk, reset_synced, write_config, out[I]);
end

endmodule
