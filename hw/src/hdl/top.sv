`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "parcore_types.svh"
`include "libstf_macros.svh"

import lynxTypes::AXI_DATA_BITS;

module Top #(
    parameter ID = 0,
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    metaIntf.m sq_rd,           // #(.STYPE(req_t))
    metaIntf.s cq_rd,           // #(.STYPE(ack_t))
    AXI4S.s rdma_in,            // #(AXI4S_DATA_BITS)
                                // NOTE: This must be axis_rreq_recv[AXI_STRM_ID]

    ready_valid_i.s in,         // #(parcore_cmd_t)

    typed_ndata_i.m out
);

// `ASSERT_ELAB($bits(parcore_cmd_t) == AXI_DATA_BITS)

// ------ RDMA reader wiring ------------------------------
ready_valid_i #(rdma_buffer_t) rdma_in_buffer ();
ndata_i #(data8_t, DATABEAT_SIZE) rdma_out ();
RDMARead #(
  .AXI_DATA_BITS(AXI_DATA_BITS),
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

assign in.ready = rdma_in_buffer.ready && in_meta.ready;
assign rdma_in_buffer.valid = in.valid && in_meta.ready;
assign in_meta.valid = in.valid && rdma_in_buffer.ready;

// Map from parcore_cmd_t to rdma_buffer_t
assign rdma_in_buffer.data.vaddr = in.data.vaddr;
assign rdma_in_buffer.data.size  = in.data.size;

// Map from parcore_cmd_t to page_metadata_t
assign in_meta.data.compression = in.data.compression;
assign in_meta.data.num_values = in.data.num_values;
assign in_meta.data.typ = in.data.typ;
assign in_meta.data.page_type = in.data.page_type;

endmodule

module MultipleTop #(
    parameter N_READERS = 1,
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    metaIntf.m sq_rd,           // #(.STYPE(req_t))
    metaIntf.s cq_rd,           // #(.STYPE(ack_t))
    AXI4S.s rdma_in[N_READERS], // #(AXI4S_DATA_BITS)
                                // NOTE: This must be axis_rreq_recv[AXI_STRM_ID]

    AXI4S.s in,                 // #(AXI_DATA_BITS)
    typed_ndata_i.m out
);

data_i #(parcore_cmd_t) cmds ();

AXIToData #(
    .data_t(parcore_cmd_t),
    .AXI_WIDTH(AXI_DATA_BITS)
) inst_axi_to_data (
    .clk(clk),
    .rst_n(rst_n),

    .in(in),
    .out(cmds)
);

for (genvar I = 0; I < N_READERS - 1; I++) begin
    Top #(
      .ID(I),
      .DATABEAT_SIZE(DATABEAT_SIZE)
    ) inst_top (
        .clk(clk),
        .rst_n(rst_n),

        .sq_rd(sq_rd),
        .cq_rd(cq_rd),
        .rdma_in(rdma_in[I])

        // TODO: wire .in(), .out()
    );
end

endmodule
