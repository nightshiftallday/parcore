`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "parcore_types.svh"
`include "libstf_macros.svh"

import lynxTypes::AXI_DATA_BITS;
import lynxTypes::N_STRM_AXI;

module Top #(
    parameter ID = 0,
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8,
    parameter AXI_WIDTH = DATABEAT_SIZE * 8
) (
    input logic clk,
    input logic rst_n,

    metaIntf.m sq_rd,           // #(.STYPE(req_t))
    metaIntf.s cq_rd,           // #(.STYPE(ack_t))
    AXI4S.s rdma_in,            // #(AXI4S_DATA_BITS)
                                // NOTE: This must be axis_rreq_recv[AXI_STRM_ID]

    ready_valid_i.s in_cmd,     // #(parcore_cmd_t)
    typed_ndata_i.m out         // #(parcore_cmd_t)
);

ready_valid_i #(parcore_cmd_t) in_cmds[1:0] ();
`READY_DUPLICATE(2, in_cmd, in_cmds)

// ------ RDMA reader wiring ------------------------------
ready_valid_i #(rdma_buffer_t) rdma_in_buffer ();
ndata_i #(data8_t, DATABEAT_SIZE) rdma_out ();
RDMARead #(
  .AXI_DATA_BITS(AXI_WIDTH),
  .AXI_STRM_ID(ID),
  .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_rdma_read (
    .clk(clk),
    .rst_n(rst_n),

    .sq_rd(sq_rd),
    .cq_rd(cq_rd),
    .rdma_in(rdma_in),

    .in(rdma_in_buffer),
    .out(rdma_out)
);

assign in_cmds[0].ready = rdma_in_buffer.ready;
assign rdma_in_buffer.valid = in_cmds[0].valid;
// Map from parcore_cmd_t to rdma_buffer_t
assign rdma_in_buffer.data.vaddr = in_cmds[0].data.in_vaddr;
assign rdma_in_buffer.data.size  = in_cmds[0].data.in_size;

// ------ Page decoder wiring -----------------------------
ready_valid_i #(page_metadata_t) in_meta ();
PageDecoder #(
    .DATABEAT_SIZE(DATABEAT_SIZE)
) inst_page_decoder (
    .clk(clk),
    .rst_n(rst_n),

    .in_meta(in_meta),
    .in(rdma_out),
    
    .out(out)
);

assign in_cmds[1].ready = in_meta.ready;
assign in_meta.valid = in_cmds[1].valid;
// Map from parcore_cmd_t to page_metadata_t
assign in_meta.data.compression = in_cmds[1].data.compression;
assign in_meta.data.num_values = in_cmds[1].data.num_values;
assign in_meta.data.typ = in_cmds[1].data.typ;
assign in_meta.data.page_type = in_cmds[1].data.page_type;

endmodule

module MultipleTop #(
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

    mem_config_i mem_config[N_READERS],
    AXI4SR.m out[N_READERS]     // #(AXI_WIDTH)
);

data_i #(parcore_cmd_t) data_in[N_READERS] ();
ready_valid_i #(parcore_cmd_t) top_in_cmds[N_READERS] ();
typed_ndata_i #(DATABEAT_SIZE) top_out[N_READERS] ();
AXI4S #(.AXI4S_DATA_BITS(AXI_WIDTH)) top_out_axi[N_READERS] (.aclk(clk));

for (genvar I = 0; I < N_READERS - 1; I++) begin
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

        .sq_rd(sq_rd),
        .cq_rd(cq_rd),
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
