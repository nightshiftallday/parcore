`timescale 1ns / 1ps

`include "parcore_types.svh"
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

/* -- USER LOGIC -------------------------------------------------------- */

/* -- INPUT ------------------------------------------------------------- */

AXI4S #(.AXI4S_DATA_BITS(512)) host_in (.aclk(aclk));
assign axis_host_recv[0].tready = host_in.tready;
assign host_in.tdata = axis_host_recv[0].tdata;
assign host_in.tkeep = axis_host_recv[0].tkeep;
assign host_in.tlast = axis_host_recv[0].tlast;
assign host_in.tvalid = axis_host_recv[0].tvalid;

ndata_i #(data8_t, 64) in ();
AXIToNData #(data8_t, 64) inst_axi_to_ndata (
    .clk(aclk),
    .rst_n(aresetn),

    .in(host_in),
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
    .clk(aclk),
    .rst_n(aresetn),

    .data(test_metadata),
    .out_data(in_meta)
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

RunDecoder #(data32_t, 16) inst_run_decoder (
    .clk(aclk),
    .rst_n(aresetn),

    .in(in),
    .in_meta(in_meta),
    .out(out)
);
