`timescale 1ns / 1ps

import parcore::*;
import parcore::rdma_buffer_t;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_wr.tie_off_s();

// -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

/* -- INPUT ------------------------------------------------------------- */

AXI4S axi_host_recv_0 (.aclk(aclk), .aresetn(aresetn));
`AXIS_ASSIGN(axis_host_recv[0], axi_host_recv_0)

AXI4S axi_rreq_recv_0 (.aclk(aclk), .aresetn(aresetn));
`AXIS_ASSIGN(axis_rreq_recv[0], axi_rreq_recv_0)

data_i #(parcore_cmd_t) data_in ();
AXIToData #(
  .data_t(parcore_cmd_t)
) inst_axi_to_data (
    .clk(clk),
    .rst_n(rst_n),

    .in(axi_host_recv_0),
    .out(data_in)
);

ready_valid_i #(parcore_cmd_t) in ();
assign data_in.ready = in.ready;
assign in.valid = data_in.valid && data_in.keep;
assign in.data = data_in.data;

/* -- OUTPUT ------------------------------------------------------------ */

AXI4S axi_host_send_0 (.aclk(aclk), .aresetn(aresetn));
`AXIS_ASSIGN(axi_host_send_0, axis_host_send[0])

ndata_i #(data8_t, 64) out_u8 ();
NDataToAXI #(data8_t, 64) inst_ndata_to_axi (
    .clk(clk),
    .rst_n(rst_n),

    .in(out_u8),
    .out(axi_host_send_0)
);

// discard typed interface
typed_ndata_i #(64) out();
`DATA_ASSIGN(out, out_u8);

/* -- DESIGN WIRING ----------------------------------------------------- */

always_ff @(posedge clk) begin
    if(rst_n) begin 
        // if (in.valid && in.ready) begin
        //     $display("< in valid: %x, ready: %x, in_addr: %d, in_size: %d, compression: %d, num_values: %d, typ: %d, page_type: %d, out_vaddr: %d, out_size: %d", in.valid, in.ready, in.data.in_vaddr, in.data.in_size, in.data.compression, in.data.num_values, in.data.typ, in.data.page_type, in.data.out_vaddr, in.data.out_size);
        // end
        //
        // if (axi_rreq_recv_0.tvalid && axi_rreq_recv_0.tready) begin
        //     $display("< rdma_in valid: %x, ready: %x, last: %x", axi_rreq_recv_0.tvalid, axi_rreq_recv_0.tready, axi_rreq_recv_0.tlast);
        // end
        //
        // if (out.valid && out.ready) begin
        //     $display("> out valid: %x, ready: %x, last: %x, keep: %x", out.valid, out.ready, out.last, out.keep);
        // end
    end
end

Top #(
    .ID(0),
    .DATABEAT_SIZE(64)
) inst_top (
    .clk(clk),
    .rst_n(rst_n),

    .sq_rd(sq_rd),
    .cq_rd(cq_rd),
    .rdma_in(axi_rreq_recv_0),

    .in_cmd(in),
    .out(out)
);
