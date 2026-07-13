`include "lynx_macros.svh"
`include "libstf_macros.svh"

import libstf::*;

// Two StreamWriters sharing one physical write channel (dest 0) through a
// StreamWriterPairArbiter: recv[0] -> writer 0 (irq id 0), recv[1] -> writer 1
// (irq id 1); both drain onto send[0]. Completions come back on the shared
// dest and are routed to the issuing writer by the arbiter.

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb sq_rd.tie_off_m();
always_comb cq_rd.tie_off_s();

for (genvar I = 2; I < N_STRM_AXI; I++) begin
    always_comb axis_host_recv[I].tie_off_s();
end
for (genvar I = 1; I < N_STRM_AXI; I++) begin
    always_comb axis_host_send[I].tie_off_m();
end

/* -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

/* -- CONFIG ------------------------------------------------------------ */
write_config_i write_configs[1](clk, rst_n);
read_config_i  read_configs [1](clk, rst_n);

GlobalConfig #(
    .SYSTEM_ID(0),
    .NUM_CONFIGS(1),
    .ADDR_SPACE_SIZES({N_STRM_AXI + 1})
) inst_config (
    .clk(clk),
    .rst_n(rst_n),

    .axi_ctrl(axi_ctrl),

    .write_configs(write_configs),
    .read_configs(read_configs)
);

mem_config_i mem_config[N_STRM_AXI](clk, rst_n);
MemConfig #(
    .NUM_STREAMS(N_STRM_AXI)
) inst_mem_config (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(write_configs[0]),
    .read_config(read_configs[0]),

    .out(mem_config)
);

for (genvar I = 2; I < N_STRM_AXI; I++) begin
    always_comb mem_config[I].tie_off_s();
end

/* -- Writer pair on channel 0 ------------------------------------------ */
AXI4S axi_host_recv[2](.aclk(clk), .aresetn(rst_n));
for (genvar I = 0; I < 2; I++) begin
    `AXIS_ASSIGN(axis_host_recv[I], axi_host_recv[I]) // AXI4SR to AXI4S
end

metaIntf #(.STYPE(req_t))     sq_wr_pair [2](.aclk(clk), .aresetn(rst_n));
metaIntf #(.STYPE(ack_t))     cq_wr_pair [2](.aclk(clk), .aresetn(rst_n));
metaIntf #(.STYPE(irq_not_t)) notify_pair[2](.aclk(clk), .aresetn(rst_n));
AXI4SR data_pair[2](.aclk(clk), .aresetn(rst_n));

for (genvar J = 0; J < 2; J++) begin
    StreamWriter #(
        .AXI_STRM_ID(0),
        .IRQ_STREAM_ID(J),
        .TRANSFER_LENGTH_BYTES(TRANSFER_SIZE_BYTES)
    ) inst_stream_writer (
        .clk(clk),
        .rst_n(rst_n),

        .sq_wr(sq_wr_pair[J]),
        .cq_wr(cq_wr_pair[J]),
        .notify(notify_pair[J]),

        .mem_config(mem_config[J]),

        .input_data(axi_host_recv[J]),
        .output_data(data_pair[J])
    );
end

StreamWriterPairArbiter inst_pair_arbiter (
    .clk(clk),
    .rst_n(rst_n),

    .sq_wr_in(sq_wr_pair),
    .cq_wr_out(cq_wr_pair),
    .data_in(data_pair),

    .sq_wr_out(sq_wr),
    .cq_wr_in(cq_wr),
    .data_out(axis_host_send[0])
);

MetaIntfArbiter #(
    .N_INTERFACES(2),
    .STYPE(irq_not_t)
) inst_notify_arbiter (
    .clk(clk),
    .rst_n(rst_n),
    .intf_in(notify_pair),
    .intf_out(notify)
);
