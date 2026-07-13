`timescale 1ns / 1ps

`include "lynx_macros.svh"

import libstf::*;

// Number of input pages driven by the test. Only the final page's `last` ends
// the chunk; all earlier page-lasts are merged across. Overridden per test via
// set_system_verilog_defines (changing it forces a re-compile).
`ifndef CPN_NUM_PAGES
`define CPN_NUM_PAGES 1
`endif

initial begin
    $display("CPN_NUM_PAGES: ", `CPN_NUM_PAGES);
end

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

logic clk;
logic rst_n;
assign clk   = aclk;
assign rst_n = aresetn;

localparam int NUM_BYTES = 512 / 8;

/* -- Input: host bytes -> ndata ---------------------------------------- */
AXI4S #(.AXI4S_DATA_BITS(512)) axis_host_recv_0(.aclk(clk), .aresetn(rst_n));
`AXIS_ASSIGN(axis_host_recv[0], axis_host_recv_0)

ndata_i #(data8_t, NUM_BYTES) cpn_in(clk, rst_n);
AXIToNData #(
    .data_t(data8_t),
    .NUM_ELEMENTS(NUM_BYTES)
) inst_axi_to_ndata (
    .clk(clk),
    .rst_n(rst_n),

    .in(axis_host_recv_0),
    .out(cpn_in)
);

/* -- Per-page flags: only the final page's flag ends the chunk ---------- */
// The pusher starts a full cycle after reset release: valid=1 across the
// release edge makes the flag FIFO register a spurious boundary write.
logic [15:0] flags_pushed;
logic push_en;
ready_valid_i #(logic) page_last(clk, rst_n);

assign page_last.data  = (flags_pushed == `CPN_NUM_PAGES - 1);
assign page_last.valid = push_en && (flags_pushed < `CPN_NUM_PAGES);

always_ff @(posedge clk) begin
    if (!rst_n) begin
        flags_pushed <= 0;
        push_en      <= 1'b0;
    end else begin
        push_en <= 1'b1;
        if (page_last.valid && page_last.ready) begin
            flags_pushed <= flags_pushed + 1;
        end
    end
end

/* -- DUT --------------------------------------------------------------- */
ndata_i #(data8_t, NUM_BYTES) cpn_out(clk, rst_n);
CrossPageNormalizer #(
    .NUM_BYTES(NUM_BYTES)
) inst_cross_page_normalizer (
    .clk(clk),
    .rst_n(rst_n),

    .page_last(page_last),

    .in(cpn_in),
    .out(cpn_out)
);

/* -- Output: ndata -> host bytes --------------------------------------- */
AXI4S #(.AXI4S_DATA_BITS(512)) axis_host_send_0(.aclk(clk), .aresetn(rst_n));
NDataToAXI #(
    .data_t(data8_t),
    .NUM_ELEMENTS(NUM_BYTES)
) inst_ndata_to_axi (
    .clk(clk),
    .rst_n(rst_n),

    .in(cpn_out),
    .out(axis_host_send_0)
);
`AXIS_ASSIGN(axis_host_send_0, axis_host_send[0])
