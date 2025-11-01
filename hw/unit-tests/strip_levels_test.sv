`timescale 1ns / 1ps

`include "parcore_types.svh"
`include "lynx_macros.svh"

import parcore::*;
import libstf::*;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
// always_comb sq_rd.tie_off_m();
// always_comb sq_wr.tie_off_m();
// always_comb cq_rd.tie_off_s();
// always_comb cq_wr.tie_off_s();

// always_comb axis_host_recv[1].tie_off_s();
// always_comb axis_host_recv[2].tie_off_s();
// always_comb axis_host_recv[3].tie_off_s();
// always_comb axis_host_recv[4].tie_off_s();
// always_comb axis_host_recv[5].tie_off_s();
// always_comb axis_host_send[1].tie_off_m();
// always_comb axis_host_send[2].tie_off_m();
// always_comb axis_host_send[3].tie_off_m();
// always_comb axis_host_send[4].tie_off_m();
// always_comb axis_host_send[5].tie_off_m();

/* -- USER LOGIC -------------------------------------------------------- */

/* -- INPUT ------------------------------------------------------------- */

AXI4S #(.AXI4S_DATA_BITS(512)) host_in (.aclk(aclk));
assign axis_host_recv[0].tready = host_in.tready;
assign host_in.tdata = axis_host_recv[0].tdata;
assign host_in.tkeep = axis_host_recv[0].tkeep;
assign host_in.tlast = axis_host_recv[0].tlast;
assign host_in.tvalid = axis_host_recv[0].tvalid;

ndata_i #(data8_t, 64) in ();
AXIToNData #(data8_t, 64) axi_to_ndata_inst (
    .clk(aclk),
    .rst_n(aresetn),

    .in(host_in),
    .out(in)
);

/* -- OUTPUT ------------------------------------------------------------ */

integer output_databeat;
AXI4S #(.AXI4S_DATA_BITS(512)) host_out (.aclk(aclk));
assign host_out.tready = axis_host_send[0].tready;
assign axis_host_send[0].tdata = host_out.tdata;
assign axis_host_send[0].tkeep = host_out.tkeep;
assign axis_host_send[0].tlast = host_out.tlast;
assign axis_host_send[0].tvalid = host_out.tvalid;
assign axis_host_send[0].tid = output_databeat;

ndata_i #(data8_t, 64) out ();
NDataToAXI #(data8_t, 64) ndata_to_axi_inst (
    .clk(aclk),
    .rst_n(aresetn),

    .in(out),
    .out(host_out)
);

/* -- DESIGN WIRING ----------------------------------------------------- */

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin 
        output_databeat  <= 0;
    end else begin
        if (host_in.tvalid && host_in.tready) begin
            $display("< in valid: %x, ready: %x, last: %x", host_in.tvalid, host_in.tready, host_in.tlast);
        end

        if (host_out.tvalid && host_out.tready) begin
            $display("> out valid: %x, ready: %x, last: %x, keep: %x", host_out.tvalid, host_out.tready, host_out.tlast, host_out.tkeep);
            output_databeat <= output_databeat + 1;

            if (host_out.tlast) begin
              $display(">>! got tlast after %d databeats", output_databeat+1);
              output_databeat <= 0;
            end
        end
    end
end

StripLevels #(64) strip_levels_inst (
    .clk(aclk),
    .rst_n(aresetn),

    .in(in),
    .out(out)
);
