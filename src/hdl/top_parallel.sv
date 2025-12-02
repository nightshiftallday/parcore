`timescale 1ns / 1ps

`include "parcore_types.svh"

import lynxTypes::AXI_DATA_BITS;
import lynxTypes::N_STRM_AXI;

module TopParallel #(
    parameter N_READERS = N_STRM_AXI,
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8,
    parameter AXI_WIDTH = DATABEAT_SIZE * 8
) (
    input logic clk,
    input logic rst_n,

    metaIntf.m sq_rd,           // #(.STYPE(req_t))
    metaIntf.s cq_rd,           // #(.STYPE(ack_t))
    metaIntf.m sq_wr,           // #(.STYPE(req_t))
    metaIntf.s cq_wr,           // #(.STYPE(ack_t))
    metaIntf.m notify,
    AXI4S.s rdma_in[N_READERS], // #(AXI_WIDTH)
                                // NOTE: This must be axis_rreq_recv

    AXI4S.s in[N_READERS],      // #(AXI_WIDTH)

    mem_config_i.s mem_config[N_READERS],
    AXI4SR.m out[N_READERS]     // #(AXI_WIDTH)
);

metaIntf #(.STYPE(req_t))     sq_rd_strm  [N_READERS](.aclk(clk));
metaIntf #(.STYPE(ack_t))     cq_rd_strm  [N_READERS](.aclk(clk));

MetaIntfArbiter #(
  .N_INTERFACES(N_READERS),
  .STYPE(req_t)
) inst_sq_rd_arbiter (
  .clk(clk),
  .rst_n(rst_n),
  .intf_in(sq_rd_strm),
  .intf_out(sq_rd)
);

CQDemultiplexer #(
  .N_STREAMS(N_READERS)
) inst_cq_rd_de_mux (
  .clk(clk),
  .rst_n(rst_n),
  .data_in(cq_rd),
  .data_out(cq_rd_strm)
);

data_i #(parcore_cmd_t) data_in[N_READERS] ();
ready_valid_i #(parcore_cmd_t) top_in_cmds[N_READERS] ();
typed_ndata_i #(DATABEAT_SIZE) top_out[N_READERS] ();
AXI4S #(.AXI4S_DATA_BITS(AXI_WIDTH)) top_out_axi[N_READERS] (.aclk(clk));

generate
for (genvar I = 0; I < N_READERS; I++) begin
    AXIToData #(
      .data_t(parcore_cmd_t),
      .AXI_WIDTH(AXI_WIDTH)
    ) inst_axi_to_data (
        .clk(clk),
        .rst_n(rst_n),

        .in(in[I]),
        .out(data_in[I])
    );

    assign data_in[I].ready = top_in_cmds[I].ready;
    assign top_in_cmds[I].valid = data_in[I].valid && data_in[I].keep;
    assign top_in_cmds[I].data = data_in[I].data;

    Top #(
        .ID(I),
        .DATABEAT_SIZE(DATABEAT_SIZE)
    ) inst_top (
        .clk(clk),
        .rst_n(rst_n),

        .sq_rd(sq_rd_strm[I]),
        .cq_rd(cq_rd_strm[I]),
        .rdma_in(rdma_in[I]),

        .in_cmd(top_in_cmds[I]),
        .out(top_out[I])
    );

    TypedNDataToAXI #(
        .DATABEAT_SIZE(DATABEAT_SIZE)
    ) inst_typed_to_axi (
        .clk(clk),
        .rst_n(rst_n),

        .in(top_out[I]),
        .out(top_out_axi[I])
    );
end
endgenerate

OutputWriter inst_output_writer (
    .clk(clk),
    .rst_n(rst_n),

    .sq_wr(sq_wr),
    .cq_wr(cq_wr),
    .notify(notify),

    .mem_config(mem_config),

    .data_in(top_out_axi),
    .data_out(out)
);

endmodule
