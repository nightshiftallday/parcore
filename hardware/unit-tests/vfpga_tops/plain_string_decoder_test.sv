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

always_comb axis_host_recv[1].tie_off_s();
for (genvar I = 2; I < N_STRM_AXI; I++) begin
    always_comb axis_host_recv[I].tie_off_s();
    always_comb axis_host_send[I].tie_off_m();
end

localparam DATABEAT_SIZE = 64;

write_config_i#(data32_t) conf_config[2] (.clk(aclk), .rst_n(aresetn));
read_config_i#(data64_t) dummy_data[2] (.clk(aclk), .rst_n(aresetn));
ready_valid_i#(offset_t)  latched_offset     (.clk(aclk), .rst_n(aresetn));
ready_valid_i#(data32_t)  latched_num_values (.clk(aclk), .rst_n(aresetn));
ready_valid_i#(plain_str_decoder_conf_t) conf (.clk(aclk), .rst_n(aresetn));
logic[AXIL_DATA_BITS - 1:0] dummy_value[2];
assign dummy_value[0] = 64'hDEADBEEFDEADBEEF;
assign dummy_value[1] = 64'hDEADBEEFDEADBEEF;

GlobalConfig#(
    .SYSTEM_ID(0),
    .NUM_CONFIGS(2),
    .ADDR_SPACE_SIZES({1, 1})
) axi_global_config (
    .clk(aclk),
    .rst_n(aresetn),

    .axi_ctrl(axi_ctrl),
    .write_configs(conf_config),
    .read_configs(dummy_data)
);

ConfigReadRegisterFile#(
    .NUM_REGS(1)
) inst_read_regs_offset (
    .clk(aclk),
    .rst_n(aresetn),

    .in(dummy_data[0]),
    .values(dummy_value[0:0])
);

ConfigReadRegisterFile#(
    .NUM_REGS(1)
) inst_read_regs_num_values (
    .clk(aclk),
    .rst_n(aresetn),

    .in(dummy_data[1]),
    .values(dummy_value[1:1])
);

ConfigWriteFIFO#(0, 1, offset_t) offset_config_fifo (
    .clk(aclk),
    .rst_n(aresetn),

    .write_config(conf_config[0]),
    .data(latched_offset)
);

ConfigWriteFIFO#(0, 1, data32_t) num_values_config_fifo (
    .clk(aclk),
    .rst_n(aresetn),

    .write_config(conf_config[1]),
    .data(latched_num_values)
);

// Join: emit one conf transaction when both fields are available.
assign conf.valid            = latched_offset.valid && latched_num_values.valid;
assign conf.data.offset      = latched_offset.data;
assign conf.data.num_values  = latched_num_values.data;
assign latched_offset.ready     = conf.ready && latched_num_values.valid;
assign latched_num_values.ready = conf.ready && latched_offset.valid;

AXI4S axi_host_recv (.aclk(aclk), .aresetn(aresetn));
`AXIS_ASSIGN(axis_host_recv[0], axi_host_recv)
ndata_i#(data8_t, DATABEAT_SIZE) in (aclk, aresetn);
AXIToNData#(data8_t, DATABEAT_SIZE) inst_axi_to_ndata (
    .clk(aclk),
    .rst_n(aresetn),

    .in(axi_host_recv),
    .out(in)
);

logic err_irq;
data_i#(data32_t) lengths (aclk, aresetn);
ndata_i#(data8_t, DATABEAT_SIZE) values (aclk, aresetn);
PlainStringDecoder plain_str_decoder (
    .clk(aclk),
    .rst_n(aresetn),

    .err_irq(err_irq),
    .conf(conf),
    .in(in),
    .out_lens(lengths),
    .out_data(values)
);

AXI4S values_to_host (.aclk(aclk), .aresetn(aresetn));
NDataToAXI#(data8_t, DATABEAT_SIZE) val_ndata_to_axi (
    .clk(aclk),
    .rst_n(aresetn),

    .in(values),
    .out(values_to_host)
);
`AXIS_ASSIGN(values_to_host, axis_host_send[0]);

ndata_i#(data8_t, 4) lengths_as_bytes (aclk, aresetn);
for (genvar i = 0; i < 4; ++i) begin
    assign lengths_as_bytes.data[i] = lengths.data[(i + 1) * 8 : i * 8];
    assign lengths_as_bytes.keep[i] = lengths.keep;
end
assign lengths.ready = lengths_as_bytes.ready;
assign lengths_as_bytes.valid = lengths.valid;
assign lengths_as_bytes.last = lengths.last;

ndata_i#(data8_t, DATABEAT_SIZE) lengths_widened (aclk, aresetn);
NDataWidthConverter#(data8_t) lengths_widener (
    .clk(aclk),
    .rst_n(aresetn),

    .in(lengths_as_bytes),
    .out(lengths_widened)
);

AXI4S lengths_to_host (.aclk(aclk), .aresetn(aresetn));
NDataToAXI#(data8_t, DATABEAT_SIZE) len_ndata_to_axi (
    .clk(aclk),
    .rst_n(aresetn),

    .in(lengths_widened),
    .out(lengths_to_host)
);
`AXIS_ASSIGN(lengths_to_host, axis_host_send[1]);
