`timescale 1ns / 1ps

import lynxTypes::*;
import reader_pkg::*;

module config_alligner #(
) (
    input logic clk,
    input logic rst_n,


    // Config interface (connects to control slave)
    input  logic cfg_valid,
    input  logic [CONFIG_WIDTH-1:0] cfg_data,
    output logic cfg_ready,

    // Header data inteface (connects to stage0)
    input  logic header_data_valid,
    input  logic [HEADER_DATA_WIDTH-1:0] header_data,
    output logic header_data_ready,

    AXI4SR.s in,
    AXI4SC.m out
);

    logic read_config;
    logic [CONFIG_WIDTH-1:0] current_config;
    logic config_valid;

    logic header_valid;
    logic [HEADER_DATA_WIDTH-1:0] header_values;

    logic need_header_values;
    assign need_header_values = WITH_HEADER_READER && current_config[HEADER_SIZE_START+15:HEADER_SIZE_START] != 0;


    logic [CONFIG_WIDTH-1:0] final_config;
    logic config_valid_comb;
    assign config_valid_comb = config_valid && header_valid;

    always_comb begin
        final_config = (config_valid) ? current_config : '0;
        if (need_header_values && header_valid) begin
            final_config[47:16] = header_values[31:0];
            final_config[PAGE_TYPE_CONFIG_INDEX+1:PAGE_TYPE_CONFIG_INDEX] = header_values[37:36];
            final_config[ENCODING_CONFIG_INDEX+3:ENCODING_CONFIG_INDEX] = header_values[35:32];
        end
    end

    assign out.tdata = in.tdata;
    assign out.tkeep = in.tkeep;
    assign out.tlast = in.tlast;
    assign out.tconfig = final_config;
    assign out.tvalid = (config_valid_comb) ? in.tvalid : 1'b0;
    assign in.tready = (config_valid_comb) ? out.tready : 1'b0;
    assign read_config = config_valid_comb && in.tvalid && in.tready && in.tlast;



    //Unneeded
    logic [CONFIG_WIDTH-1:0] next_config;
    logic next_config_valid;
    logic next_header_valid;
    logic [HEADER_DATA_WIDTH-1:0] next_header_values;

    // Config Ring Buffer
    config_ring_buffer #(
        .CONFIG_WIDTH(CONFIG_WIDTH),
        .DEPTH(BUFFER_DEPTH)
    ) config_fifo (
        .clk(clk),
        .rst(~rst_n),
        .cfg_valid(cfg_valid),
        .cfg_data(cfg_data),
        .cfg_ready(cfg_ready),
        .read_config(read_config),
        .current_config(current_config),
        .config_valid(config_valid),
        .next_config(next_config),
        .next_config_valid(next_config_valid),
        .debug_wr_ptr(debug_wr_ptr),
        .debug_rd_ptr(debug_rd_ptr)
    );

    // Header Data Ring Buffer
    config_ring_buffer #(
        .CONFIG_WIDTH(HEADER_DATA_WIDTH),
        .DEPTH(8)
    ) header_fifo (
        .clk(clk),
        .rst(~rst_n),
        .cfg_valid(header_data_valid),
        .cfg_data(header_data),
        .cfg_ready(header_data_ready),
        .read_config(read_config),
        .current_config(header_values),
        .config_valid(header_valid),
        .next_config(next_header_values),
        .next_config_valid(next_header_valid)
    );



    logic [$clog2(BUFFER_DEPTH)-1:0] debug_wr_ptr;
    logic [$clog2(BUFFER_DEPTH)-1:0] debug_rd_ptr;

    // ------------------------------------------------------------
    // ila_alligner ila_alligner_inst (
    //     .clk(clk),

    //     // Stage2 input stream
    //     .probe0(in.tdata),
    //     .probe1(in.tvalid),
    //     .probe2(in.tready),
    //     .probe3(in.tlast),

    //     // Stage2 output stream
    //     .probe4(out.tdata),
    //     .probe5(out.tvalid),
    //     .probe6(out.tready),
    //     .probe7(out.tlast),
    //     .probe8(out.tconfig),

    //     // Stage2 internal state
    //     .probe9({config_valid, header_valid, read_config}),
    //     .probe10({next_config_valid, next_header_valid}),
    //     .probe11(current_config),
    //     .probe12({cfg_valid, cfg_ready}),
    //     .probe13(debug_wr_ptr), // $clog2(BUFFER_DEPTH)-1 bits
    //     .probe14(debug_rd_ptr), // $clog2(BUFFER_DEPTH)-1 bits
    //     .probe15(rst_n)
    // );



endmodule