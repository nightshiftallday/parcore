`timescale 1ns / 1ps

`include "parcore_types.svh"
import parcore::*;

import libstf::data32_t;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

/* -- INPUT ------------------------------------------------------------- */

always_comb axis_host_recv[0].tie_off_s();

typedef struct packed {
    data32_t data;
    rle_count_t meta;
} tagged_t;

tagged_t test_data[3:0];
assign test_data = '{
    '{data: 98412, meta: 127},
    '{data: 11, meta: 54},
    '{data: 1337, meta: 7},
    '{data: 1024, meta: 64}
};

ready_valid_i #(tagged_t) ready_valid_in ();
ReadyValidCyclicDriver #(tagged_t, 4) inst_in_driver (
    .clk(aclk),
    .rst_n(aresetn),

    .data(test_data),
    .out_data(ready_valid_in)
);

tagged_i #(data32_t, $bits(rle_count_t)) in ();
assign ready_valid_in.ready = in.ready;
assign in.valid = ready_valid_in.valid;
assign in.data = ready_valid_in.data.data;
assign in.tag = ready_valid_in.data.meta;

/* -- OUTPUT ------------------------------------------------------------ */

integer output_databeat;
AXI4S #(.AXI4S_DATA_BITS(512)) host_out (.aclk(aclk));
assign host_out.tready = axis_host_send[0].tready;
assign axis_host_send[0].tdata = host_out.tdata;
assign axis_host_send[0].tkeep = host_out.tkeep;
assign axis_host_send[0].tlast = host_out.tlast;
assign axis_host_send[0].tvalid = host_out.tvalid;
assign axis_host_send[0].tid = output_databeat;

ndata_i #(data32_t, 16) out ();
NDataToAXI #(data32_t, 16) inst_ndata_to_axi (
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
        if (in.valid && in.ready) begin
            $display("< in valid: %x, ready: %x", in.valid, in.ready);
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

ExpandRLE #(data32_t, 16) inst_expand_rle (
    .clk(aclk),
    .rst_n(aresetn),

    .in(in),
    .out(out)
);
