`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;
import reader_pkg::*;

module reader_top #(

)(
    input logic clk,
    input logic rst_n,
    // Per-unit performance reset
    input logic perf_rst,

    output logic                 cfg_ready,
    input logic                  cfg_valid,
    input logic [CONFIG_WIDTH-1:0] cfg_data,


    AXI4SR.s in_stream,
    AXI4SR.m out_stream,
    // Performance
    output logic [63:0] pages_done_count,

    // Debug outputs (only reader states for top-level visibility)
    output logic [2:0] debug_rle_state,
    output logic [2:0] debug_dict_4_state,
    output logic [2:0] debug_dict_8_state
);

logic header_data_valid;
logic [HEADER_DATA_WIDTH-1:0] header_data;
logic header_data_ready;

AXI4SR stage0_out(clk);
AXI4SC stage0_to_stage1(clk);
AXI4SC stage1_to_stage2(clk);
AXI4SC stage2_to_output(clk);

logic cfg_valid_all, cfg_ready_1, cfg_ready_2;
logic cfg_ready_all;
assign cfg_ready_all = cfg_ready_1 & cfg_ready_2;
assign cfg_valid_all = cfg_valid & cfg_ready_all;
assign cfg_ready = cfg_ready_all;

// Stages
generate if (WITH_HEADER_READER) begin
page_header_reader stage0 (
    .clk(clk),
    .rst_n(rst_n),

    .cfg_ready(cfg_ready_1),
    .cfg_valid(cfg_valid_all),
    .cfg_data(cfg_data),

    .header_data_ready(header_data_ready),
    .header_data(header_data),
    .header_data_valid(header_data_valid),

    .in_stream(in_stream),
    .out_stream(stage0_out)
);
config_alligner config_alligner (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_valid(cfg_valid_all),
        .cfg_data(cfg_data),
        .cfg_ready(cfg_ready_2),

        .header_data_valid(header_data_valid),
        .header_data(header_data),
        .header_data_ready(header_data_ready),

        .in(stage0_out),
        .out(stage0_to_stage1)
);


end else begin
    config_alligner config_alligner (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_valid(cfg_valid),
        .cfg_data(cfg_data),
        .cfg_ready(cfg_ready),

        .header_data_valid(1'b1),
        .header_data('0),
        .header_data_ready(),

        .in(in_stream),
        .out(stage0_to_stage1)
    );


end endgenerate


decompressor stage1 (
    .clk(clk),
    .rst_n(rst_n),

    .in_stream(stage0_to_stage1),
    .out_stream(stage1_to_stage2)
);

multi_reader stage2 (
    .clk(clk),
    .rst_n(rst_n),
    .perf_rst(perf_rst),

    .in_stream(stage1_to_stage2),
    .out_stream(stage2_to_output),
    .pages_done_count(pages_done_count),
    .debug_rle_state(debug_rle_state),
    .debug_dict_4_state(debug_dict_4_state),
    .debug_dict_8_state(debug_dict_8_state)
);

assign out_stream.tdata = stage2_to_output.tdata;
assign out_stream.tkeep = stage2_to_output.tkeep;
assign out_stream.tlast = stage2_to_output.tlast;
assign out_stream.tvalid = stage2_to_output.tvalid;
assign stage2_to_output.tready = out_stream.tready;
assign out_stream.tid = in_stream.tid;



endmodule