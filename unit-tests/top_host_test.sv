`include "parcore_types.svh"
`include "lynx_macros.svh"
`include "libstf_macros.svh"

import libstf::data8_t;
import parcore::parcore_cmd_t;
import parcore::page_metadata_t;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

always_comb axis_host_send[1].tie_off_m();
// always_comb axis_host_send[2].tie_off_m();
// always_comb axis_host_send[3].tie_off_m();

// always_comb axis_host_recv[2].tie_off_s();
// always_comb axis_host_recv[3].tie_off_s();

// -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

/* -- INPUT ------------------------------------------------------------- */

AXI4S axi_host_recv_0 (.aclk(aclk), .aresetn(aresetn));
`AXIS_ASSIGN(axis_host_recv[0], axi_host_recv_0)

data_i #(parcore_cmd_t) data_in ();
AXIToData #(
  .data_t(parcore_cmd_t)
) inst_axi_to_data (
    .clk(clk),
    .rst_n(rst_n),

    .in(axi_host_recv_0),
    .out(data_in)
);

ready_valid_i #(page_metadata_t) in_meta ();
assign data_in.ready = in_meta.ready;
assign in_meta.valid = data_in.valid && data_in.keep;
// Map from parcore_cmd_t to page_metadata_t
assign in_meta.data.compression = data_in.data.compression;
assign in_meta.data.num_values = data_in.data.num_values;
assign in_meta.data.typ = data_in.data.typ;
assign in_meta.data.page_type = data_in.data.page_type;

AXI4S axi_host_recv_1 (.aclk(aclk), .aresetn(aresetn));
`AXIS_ASSIGN(axis_host_recv[1], axi_host_recv_1)

ndata_i #(data8_t, 64) in ();
AXIToNData #(data8_t, 64) inst_axi_to_ndata (
    .clk(clk),
    .rst_n(rst_n),

    .in(axi_host_recv_1),
    .out(in)
);

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

PageDecoder #(
    .DATABEAT_SIZE(64)
) inst_page_decoder (
    .clk(clk),
    .rst_n(rst_n),

    .in_meta(in_meta),
    .in(in),
    
    .out(out)
);
