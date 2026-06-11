`timescale 1ns / 1ps

`include "lynx_macros.svh"
`include "libstf_macros.svh"

import parcore::*;
import libstf::data8_t;
import libstf::data32_t;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

for (genvar I = 2; I < N_STRM_AXI; I++) begin
    always_comb axis_host_recv[I].tie_off_s();
    always_comb axis_host_send[I].tie_off_m();
end

always_comb axis_host_recv[1].tie_off_s();

/* -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

/* -- CONFIG ------------------------------------------------------------ */
write_config_i write_configs[1](.*);
read_config_i  read_configs [1](.*);
GlobalConfig #(
    .SYSTEM_ID(PARCORE_SYSTEM_ID),
    .NUM_CONFIGS(1),
    .ADDR_SPACE_SIZES({COLUMN_CHUNK_DECODER_READ_REGS(1)})
) inst_config (
    .clk(clk),
    .rst_n(rst_n),

    .axi_ctrl(axi_ctrl),

    .write_configs(write_configs),
    .read_configs(read_configs)
);

// No decoder is instantiated in this test, so the profiling counters are tied off.
decoder_profile_t profile[1];
assign profile[0] = '0;

ready_valid_i #(column_chunk_conf_t) chunk_conf[1](.*);
ColumnChunkDecoderConfig #(
    .NUM_DECODERS(1)
) inst_column_chunk_decoder_config (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(write_configs[0]),
    .read_config(read_configs[0]),

    .profile(profile),

    .out(chunk_conf)
);

/* -- INPUT (stream 0): raw column-chunk bytes -------------------------- */

AXI4S axi_host_recv_0 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axis_host_recv[0], axi_host_recv_0)

ndata_i #(data8_t, 64) in(clk, rst_n);
AXIToNData #(data8_t, 64) inst_axi_to_ndata (
    .clk(clk),
    .rst_n(rst_n),

    .in(axi_host_recv_0),
    .out(in)
);

/* -- DUT --------------------------------------------------------------- */

ndata_i #(data8_t, 64) payload(clk, rst_n);
ready_valid_i #(page_conf_t) page_conf(.*);

PageHeaderParser #(
    .NUM_BYTES(64)
) inst_dut (
    .clk(clk),
    .rst_n(rst_n),

    .chunk_conf(chunk_conf[0]),
    .in(in),
    .out(payload),
    .page_conf(page_conf)
);

/* -- OUTPUT (stream 0): stripped payload bytes ------------------------- */

AXI4S axi_host_send_0 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axi_host_send_0, axis_host_send[0])

NDataToAXI #(data8_t, 64) inst_ndata_to_axi_payload (
    .clk(clk),
    .rst_n(rst_n),

    .in(payload),
    .out(axi_host_send_0)
);

/* -- OUTPUT (stream 1): page_conf records ------------------------------ */
// Each page emits a 6-byte record: page_type(1B) | num_values(4B LE) | last(1B)
// Serialised as a single 64-byte NData beat (first 6 bytes valid, rest invalid).

AXI4S axi_host_send_1 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axi_host_send_1, axis_host_send[1])

ndata_i #(data8_t, 64) page_conf_stream(clk, rst_n);

// Small FSM: capture page_conf, pack into a beat, send it.
logic       pc_pending;
data8_t     pc_buf [5:0];

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_pending <= 1'b0;
    end else begin
        // Consume page_conf when not already holding a pending beat
        if (!pc_pending && page_conf.valid) begin
            pc_buf[0] <= data8_t'(page_conf.data.page_type);
            pc_buf[1] <= data8_t'(page_conf.data.num_values[7:0]);
            pc_buf[2] <= data8_t'(page_conf.data.num_values[15:8]);
            pc_buf[3] <= data8_t'(page_conf.data.num_values[23:16]);
            pc_buf[4] <= data8_t'(page_conf.data.num_values[31:24]);
            pc_buf[5] <= data8_t'(page_conf.data.last);
            pc_pending <= 1'b1;
        end else if (pc_pending && page_conf_stream.ready) begin
            pc_pending <= 1'b0;
        end
    end
end

assign page_conf.ready = !pc_pending;

always_comb begin
    page_conf_stream.valid = pc_pending;
    page_conf_stream.last  = 1'b1;
    page_conf_stream.keep  = 64'h3f; // low 6 bytes valid
    for (int i = 0; i < 64; i++)
        page_conf_stream.data[i] = (i < 6) ? pc_buf[i] : 8'h00;
end

NDataToAXI #(data8_t, 64) inst_ndata_to_axi_conf (
    .clk(clk),
    .rst_n(rst_n),

    .in(page_conf_stream),
    .out(axi_host_send_1)
);
