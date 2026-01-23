`timescale 1ns / 1ps

`include "lynx_macros.svh"

import parcore::run_decoder_metadata_t;
import libstf::data8_t;
import libstf::data32_t;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

/* -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

/* -- INPUT ------------------------------------------------------------- */

AXI4S axi_host_recv_0 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axis_host_recv[0], axi_host_recv_0)

ndata_i #(data8_t, 64) in ();
AXIToNData #(data8_t, 64) inst_axi_to_ndata (
    .clk(clk),
    .rst_n(rst_n),

    .in(axi_host_recv_0),
    .out(in)
);

ready_valid_i #(run_decoder_metadata_t) in_meta ();

run_decoder_metadata_t test_metadata[2:0];
assign test_metadata = '{
    '{bit_width: 8, offset: 8, num_values: 802},
    '{bit_width: 4, offset: 8, num_values: 150},
    '{bit_width: 4, offset: 8, num_values: 145}
};

ReadyValidCyclicDriver #(run_decoder_metadata_t, 3) inst_meta_driver (
    .clk(clk),
    .rst_n(rst_n),

    .data(test_metadata),
    .out_data(in_meta)
);

/* -- OUTPUT ------------------------------------------------------------ */

AXI4S axi_host_send_0 (.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axi_host_send_0, axis_host_send[0])

ndata_i #(data32_t, 16) out ();
NDataToAXI #(data32_t, 16) inst_ndata_to_axi (
    .clk(clk),
    .rst_n(rst_n),

    .in(out),
    .out(axi_host_send_0)
);

/* -- DESIGN WIRING ----------------------------------------------------- */

RunDecoder #(data32_t, 16) inst_run_decoder (
    .clk(clk),
    .rst_n(rst_n),

    .in(in),
    .in_meta(in_meta),
    .out(out)
);
