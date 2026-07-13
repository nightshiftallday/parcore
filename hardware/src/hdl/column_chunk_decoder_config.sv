`timescale 1ns / 1ps

import libstf::*;
import parcore::*;

`include "libstf_macros.svh"
`include "config_macros.svh"

interface decoder_profile_i;
    decoder_profile_t counters;
    logic             stop;

    modport m (
        input  stop,
        output counters
    );

    modport s (
        input  counters,
        output stop
    );
endinterface

module ColumnChunkDecoderConfig #(
    parameter NUM_DECODERS
) (
    input logic clk,
    input logic rst_n,

    write_config_i.s write_config,
    read_config_i.s  read_config,

    ready_valid_i.m out[NUM_DECODERS], // #(column_chunk_conf_t)

    decoder_profile_i.s profile[NUM_DECODERS]
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
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 0] = profile[I].counters.in.handshakes_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 1] = profile[I].counters.in.starved_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 2] = profile[I].counters.in.stalled_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 3] = profile[I].counters.in.idle_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 4] = profile[I].counters.out.handshakes_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 5] = profile[I].counters.out.starved_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 6] = profile[I].counters.out.stalled_cycles;
    assign values[NUM_INFO_REGS + NUM_PROFILE_REGS * I + 7] = profile[I].counters.out.idle_cycles;
end

ConfigReadRegisterFile #(
    .NUM_REGS(NUM_READ_REGS)
) inst_read_regs (
    .clk(clk),
    .rst_n(reset_synced),

    .in(read_config),
    .values(values)
);

// -- Profile stop ---------------------------------------------------------------------------------
// The host reads a decoder's 8 profile counters in ascending order. We detect the last read 
// handshake and pulse stop[I] so the profilers reset once the full snapshot has been read out.
logic read_handshake;
assign read_handshake = read_config.read_valid && read_config.read_ready;

for (genvar I = 0; I < NUM_DECODERS; I++) begin
    localparam int LAST_PROFILE_REG = NUM_INFO_REGS + NUM_PROFILE_REGS * (I + 1) - 1;
    assign profile[I].stop = read_handshake && (read_config.read_addr == LAST_PROFILE_REG);
end

// -- Write ----------------------------------------------------------------------------------------
// Two write registers per decoder: register 2I = chunk's heap base address
// register 2I+1 = the packed {compression, num_values, typ}
// Fixed-width chunks may skip the address write. ()
for (genvar I = 0; I < NUM_DECODERS; I++) begin : gen_conf
    vaddress_t heap_base_addr;
    logic      conf_valid;

    always_ff @(posedge clk) begin
        if (reset_synced == 1'b0) begin
            heap_base_addr <= '0;
        end else if (write_config.valid && write_config.addr == 2 * I) begin
            heap_base_addr <= vaddress_t'(write_config.data);
        end
    end

    assign conf_valid = write_config.valid && write_config.addr == 2 * I + 1;

    ready_valid_i #(column_chunk_conf_t) internal(clk, reset_synced);
    logic [$bits(column_chunk_conf_t) - 1:0] fifo_out;

    MehdiFIFO #(
        .DEPTH(MAX_NUM_ENQUEUED_BUFFERS),
        .WIDTH($bits(column_chunk_conf_t))
    ) inst_conf_fifo (
        .i_clk(clk),
        .i_rst_n(reset_synced),

        .i_data({heap_base_addr, write_config.data[35:0]}),
        .i_valid(conf_valid),
        .i_ready(),

        .o_data(fifo_out),
        .o_valid(internal.valid),
        .o_ready(internal.ready),

        .o_filling_level()
    );
    assign internal.data = column_chunk_conf_t'(fifo_out);

    ReadyValidShiftRegister #(column_chunk_conf_t, 1) inst_conf_reg (
        .clk(clk),
        .rst_n(reset_synced),

        .in(internal),
        .out(out[I])
    );
end

endmodule
