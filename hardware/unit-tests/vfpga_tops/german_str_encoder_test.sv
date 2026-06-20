`timescale 1ns / 1ps

`include "lynx_macros.svh"
`include "libstf_macros.svh"

import parcore::*;
import libstf::*;
import lynxTypes::*;

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

/* -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

localparam int DATABEAT_SIZE = 64; // STREAM_WIDTH in bytes

/* -- CONFIG ------------------------------------------------------------ */
write_config_i conf_config[2] (.clk(clk), .rst_n(rst_n));
read_config_i  dummy_data [2] (.clk(clk), .rst_n(rst_n));

ready_valid_i #(offset_t) latched_offset      (.clk(clk), .rst_n(rst_n));
ready_valid_i #(data64_t) latched_buffer_addr (.clk(clk), .rst_n(rst_n));
ready_valid_i #(german_str_encoder_conf_t) conf (.clk(clk), .rst_n(rst_n));

logic[AXIL_DATA_BITS - 1:0] dummy_value[2];
assign dummy_value[0] = 64'hDEADBEEFDEADBEEF;
assign dummy_value[1] = 64'hDEADBEEFDEADBEEF;

GlobalConfig #(
    .SYSTEM_ID(0),
    .NUM_CONFIGS(2),
    .ADDR_SPACE_SIZES({1, 1})
) axi_global_config (
    .clk(clk),
    .rst_n(rst_n),

    .axi_ctrl(axi_ctrl),
    .write_configs(conf_config),
    .read_configs(dummy_data)
);

ConfigReadRegisterFile #(
    .NUM_REGS(1)
) inst_read_regs_offset (
    .clk(clk),
    .rst_n(rst_n),

    .in(dummy_data[0]),
    .values(dummy_value[0:0])
);

ConfigReadRegisterFile #(
    .NUM_REGS(1)
) inst_read_regs_buffer_addr (
    .clk(clk),
    .rst_n(rst_n),

    .in(dummy_data[1]),
    .values(dummy_value[1:1])
);

ConfigWriteFIFO #(0, 1, offset_t) offset_config_fifo (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(conf_config[0]),
    .data(latched_offset)
);

ConfigWriteFIFO #(0, 1, data64_t) buffer_addr_config_fifo (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(conf_config[1]),
    .data(latched_buffer_addr)
);

// Join: emit one conf transaction when both fields are available.
assign conf.valid            = latched_offset.valid && latched_buffer_addr.valid;
assign conf.data.offset      = latched_offset.data;
assign conf.data.buffer_addr = latched_buffer_addr.data;
assign latched_offset.ready      = conf.ready && latched_buffer_addr.valid;
assign latched_buffer_addr.ready = conf.ready && latched_offset.valid;

/* -- INPUT (stream 0): concatenated string bytes ----------------------- */
AXI4S axi_host_recv_0 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axis_host_recv[0], axi_host_recv_0)

ndata_i #(data8_t, DATABEAT_SIZE) in_data (.clk(clk), .rst_n(rst_n));
AXIToNData #(data8_t, DATABEAT_SIZE) inst_axi_to_ndata_data (
    .clk(clk),
    .rst_n(rst_n),

    .in(axi_host_recv_0),
    .out(in_data)
);

/* -- INPUT (stream 1): string lengths (4-byte LE each) ----------------- */
AXI4S axi_host_recv_1 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axis_host_recv[1], axi_host_recv_1)

data_i #(data32_t) in_lens_with_bubbles (.clk(clk), .rst_n(rst_n));
AXIToData #(data32_t) inst_axi_to_ndata_lens (
    .clk(clk),
    .rst_n(rst_n),

    .in(axi_host_recv_1),
    .out(in_lens_with_bubbles)
);

data_i #(data32_t) in_lens (.clk(clk), .rst_n(rst_n));

assign in_lens.valid = in_lens_with_bubbles.valid && in_lens_with_bubbles.keep;
assign in_lens_with_bubbles.ready = in_lens.ready;
assign in_lens.data = in_lens_with_bubbles.data;
assign in_lens.keep = in_lens_with_bubbles.keep;
assign in_lens.last  = in_lens_with_bubbles.last;

data_i  #(german_str_t)           out_strings (.clk(clk), .rst_n(rst_n));
ndata_i #(data8_t, DATABEAT_SIZE) out_data    (.clk(clk), .rst_n(rst_n));

GermanStringEncoder #(
    .STREAM_WIDTH(DATABEAT_SIZE)
) inst_dut (
    .clk(clk),
    .rst_n(rst_n),

    .in_config(conf),
    .in_lens(in_lens),
    .in_data(in_data),
    .out_strings(out_strings),
    .out_data(out_data)
);

AXI4S axi_host_send_0 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axi_host_send_0, axis_host_send[0])

logic [$bits(german_str_t)-1:0] strings_bits;
assign strings_bits = out_strings.data;

ndata_i #(data8_t, 16) strings_as_bytes (.clk(clk), .rst_n(rst_n));
for (genvar i = 0; i < 16; i++) begin
    assign strings_as_bytes.data[i] = strings_bits[i*8 +: 8];
    assign strings_as_bytes.keep[i] = out_strings.keep;
end
assign out_strings.ready      = strings_as_bytes.ready;
assign strings_as_bytes.valid = out_strings.valid;
assign strings_as_bytes.last  = out_strings.last;

ndata_i #(data8_t, DATABEAT_SIZE) strings_widened (.clk(clk), .rst_n(rst_n));
NDataWidthConverter #(data8_t) strings_widener (
    .clk(clk),
    .rst_n(rst_n),

    .in(strings_as_bytes),
    .out(strings_widened)
);

NDataToAXI #(data8_t, DATABEAT_SIZE) inst_ndata_to_axi_strings (
    .clk(clk),
    .rst_n(rst_n),

    .in(strings_widened),
    .out(axi_host_send_0)
);

AXI4S axi_host_send_1 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axi_host_send_1, axis_host_send[1])

NDataToAXI #(data8_t, DATABEAT_SIZE) inst_ndata_to_axi_data (
    .clk(clk),
    .rst_n(rst_n),

    .in(out_data),
    .out(axi_host_send_1)
);
