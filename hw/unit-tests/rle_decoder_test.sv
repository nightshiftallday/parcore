`timescale 1ns / 1ps

`include "parcore_types.svh"
import parcore::*;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */

/* -- INPUT ------------------------------------------------------------- */

always_comb axis_host_recv[0].tie_off_s();

bitdata_i #(32, rle_count_t) in ();

logic[31:0] test_data[3:0];
assign test_data = '{ 98412, 11, 1337, 1024 };

rle_count_t test_meta[3:0];
assign test_meta = '{ 127, 54, 7, 64 };

BitdataCyclicDriver #(32, rle_count_t, 4) inst_in_driver (
    .clk(aclk),
    .rst_n(aresetn),

    .data(test_data),
    .meta(test_meta),
    .out_data(in)
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

ndata_i #(logic[31:0], 16) out ();
NDataToAXI #(logic[31:0], 16) inst_ndata_to_axi (
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
        // if (host_in.tvalid && host_in.tready) begin
        //     $display("< in valid: %x, ready: %x, last: %x", host_in.tvalid, host_in.tready, host_in.tlast);
        // end

        if (host_out.tvalid && host_out.tready) begin
            // $display("> out valid: %x, ready: %x, last: %x, keep: %x", host_out.tvalid, host_out.tready, host_out.tlast, host_out.tkeep);
            output_databeat <= output_databeat + 1;

            if (host_out.tlast) begin
              // $display(">>! got tlast after %d databeats", output_databeat+1);
              output_databeat <= 0;
            end
        end
    end
end

ExpandRLE #(32, 16) inst_expand_rle (
    .clk(aclk),
    .rst_n(aresetn),

    .in(in),
    .out(out)
);
