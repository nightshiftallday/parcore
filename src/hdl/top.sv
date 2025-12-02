`timescale 1ns / 1ps

`include "parcore_types.svh"
`include "libstf_macros.svh"

import lynxTypes::AXI_DATA_BITS;

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
