// -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

// -- Configuration --------------------------------------------------------------------------------
config_i configs[1]();
GlobalConfig #(
    .NUM_CONFIGS(1),
    .ADDR_SPACE_BOUNDS({0, 2 * N_STRM_AXI})
) inst_config (
    .clk(clk),
    .rst_n(rst_n),

    .axi_ctrl(axi_ctrl),
    .configs(configs)
);

mem_config_i mem_config[N_STRM_AXI]();
MemConfig #(
    .NUM_STREAMS(N_STRM_AXI)
) inst_mem_config (
    .clk(clk),
    .rst_n(rst_n),

    .conf(configs[0]),
    .out(mem_config)
);

/* -- INPUT ------------------------------------------------------------- */

AXI4S axi_host_recv[N_STRM_AXI](.aclk(clk));
generate
for (genvar I = 0; I < N_STRM_AXI; I++) begin
    `AXIS_ASSIGN(axis_host_recv[I], axi_host_recv[I]) // AXI4SR to AXI4S
end
endgenerate

AXI4S axi_rreq_recv[N_STRM_AXI](.aclk(clk));
generate
for (genvar I = 0; I < N_RDMA_AXI; I++) begin
    `AXIS_ASSIGN(axis_rreq_recv[I], axi_rreq_recv[I]) // AXI4SR to AXI4S
end
endgenerate

`ASSERT_ELAB(N_STRM_AXI == N_RDMA_AXI)

/* -- DESIGN WIRING ----------------------------------------------------- */

MultipleTop #(
    .N_READERS(N_STRM_AXI),
    .DATABEAT_SIZE(64)
) inst_multiple_top (
    .clk(clk),
    .rst_n(rst_n),

    .sq_rd(sq_rd),
    .cq_rd(cq_rd),
    .sq_wr(sq_wr),
    .cq_wr(cq_wr),
    .notify(notify),
    .rdma_in(axi_rreq_recv),

    .in(axi_host_recv),
    .mem_config(mem_config),
    .out(axis_host_send)
);
