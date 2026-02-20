`timescale 1ns / 1ps

`include "lynx_macros.svh"

import parcore::*;
import libstf::*;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

for (genvar I = 1; I < N_STRM_AXI; I++) begin
    always_comb axis_host_recv[I].tie_off_s();
    always_comb axis_host_send[I].tie_off_m();
end

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

ready_valid_i #(run_decoder_config_t) conf ();

// TODO: configure using the RunDecoderConfig module

run_decoder_config_t test_conf[2:0];
assign test_conf = '{
    '{bit_width: 8, offset: 8, num_values: 802},
    '{bit_width: 4, offset: 8, num_values: 150},
    '{bit_width: 4, offset: 8, num_values: 145}
};

ReadyValidCyclicDriver #(run_decoder_config_t, 3) inst_conf_driver (
    .clk(clk),
    .rst_n(rst_n),

    .data(test_conf),
    .out_data(conf)
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
    .conf(conf),
    .out(out)
);
