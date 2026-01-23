`timescale 1ns / 1ps

import libstf::data8_t;

import parcore::*;
import libstf::*;


/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[1].tie_off_m();

/* -- INPUT ------------------------------------------------------------- */

AXI4S #(.AXI4S_DATA_BITS(512)) host_in (.aclk(aclk), .aresetn(aresetn));
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

/* -- OUTPUT ------------------------------------------------------------ */

integer output_databeat;
AXI4S #(.AXI4S_DATA_BITS(512)) host_out (.aclk(aclk), .aresetn(aresetn));
assign host_out.tready = axis_host_send[0].tready;
assign axis_host_send[0].tdata = host_out.tdata;
assign axis_host_send[0].tkeep = host_out.tkeep;
assign axis_host_send[0].tlast = host_out.tlast;
assign axis_host_send[0].tvalid = host_out.tvalid;
assign axis_host_send[0].tid = output_databeat;

ndata_i #(data8_t, 64) out ();
NDataToAXI #(data8_t, 64) inst_ndata_to_axi (
    .clk(aclk),
    .rst_n(aresetn),

    .in(out),
    .out(host_out)
);


/* -- DESIGN WIRING ----------------------------------------------------- */

ready_valid_i #(page_metadata_t) in_meta ();
ready_valid_i #(page_metadata_t) out_meta ();
// tie off out_meta as we're not going to read its output
assign out_meta.ready = 1;

page_metadata_t test_metadata[2:0];
assign test_metadata = '{
    '{compression: COMPRESSION_SNAPPY, num_values: 0, typ: INT32_T, page_type: PAGE_TYPE_HYBRID},
    '{compression: COMPRESSION_RAW, num_values: 0, typ: INT32_T, page_type: PAGE_TYPE_HYBRID},
    '{compression: COMPRESSION_SNAPPY, num_values: 0, typ: INT32_T, page_type: PAGE_TYPE_HYBRID}
};

ReadyValidCyclicDriver #(page_metadata_t, 3) inst_meta_driver (
    .clk(aclk),
    .rst_n(aresetn),

    .data(test_metadata),
    .out_data(in_meta)
);

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin 
        output_databeat  <= 0;
    end else begin
        // if (host_in.tvalid && host_in.tready) begin
        //     $display("< in valid: %x, ready: %x, last: %x", host_in.tvalid, host_in.tready, host_in.tlast);
        // end

        if (host_out.tvalid && host_out.tready) begin
            // $display("> out valid: %x, ready: %x, last: %x", host_out.tvalid, host_out.tready, host_out.tlast);
            output_databeat <= output_databeat + 1;

            if (host_out.tlast) begin
              // $display(">>! got tlast after %d databeats", output_databeat+1);
              output_databeat <= 0;
            end
        end
    end
end

Decompressor #(64) inst_decompressor (
    .clk(aclk),
    .rst_n(aresetn),

    .in(in),
    .in_meta(in_meta),

    .out(out),
    .out_meta(out_meta)
);
