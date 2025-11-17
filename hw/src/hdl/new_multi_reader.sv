`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;
import reader_pkg::*;

module new_multi_reader (
    input logic clk,
    input logic rst_n,

    AXI4SC.s  in_stream,
    AXI4SC.m out_streams
);
    AXI4SC in_stream_ff(clk);

    OverflowRegister input_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in(in_stream),
        .out(in_stream_ff)
    );

    logic inside_pkt_ff;  // 1 after first beat until TLAST (accepted)
    // Convenience
    wire beat_accepted = in_stream_ff.tvalid && in_stream_ff.tready;

    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        inside_pkt_ff <= 1'b0;
    end else if (beat_accepted) begin
        if (!inside_pkt_ff) begin
        // First accepted beat (SOP): be inside the packet only if not last
        inside_pkt_ff <= ~in_stream_ff.tlast;
        end else begin
        // Inside packet: drop to 0 when the last beat is accepted
        if (in_stream_ff.tlast) inside_pkt_ff <= 1'b0;
        end
    end
    end

    wire first_beat_comb = beat_accepted && !inside_pkt_ff;

    //Input arbiter
    logic [CONFIG_WIDTH-1:0] input_config;
    assign input_config = in_stream_ff.tconfig;

    logic [1:0] page_type;
    logic [3:0] encoding;
    logic [3:0] byte_width;
    assign page_type = input_config[PAGE_TYPE_CONFIG_INDEX+1:PAGE_TYPE_CONFIG_INDEX];
    assign encoding = input_config[ENCODING_CONFIG_INDEX+3:ENCODING_CONFIG_INDEX];
    // Byte width is not present in header values
    assign byte_width = input_config[BYTE_WIDTH_CONFIG_INDEX+3:BYTE_WIDTH_CONFIG_INDEX];

    wire page_data_rle_1     = (page_type == 2'd0 || page_type == 2'd3) && encoding == 4'd3 && byte_width == 4'd1;
    wire page_data_rledict_4 = (page_type == 2'd0 || page_type == 2'd3) && encoding == 4'd8 && byte_width == 4'd4;
    wire page_data_rledict_8 = (page_type == 2'd0 || page_type == 2'd3) && encoding == 4'd8 && byte_width == 4'd8;
    wire page_dict_plain_4   = page_type == 2'd2 && encoding == 4'd0 && byte_width == 4'd4;
    wire page_dict_plain_8   = page_type == 2'd2 && encoding == 4'd0 && byte_width == 4'd8;
    wire plain_page          = (page_type == 2'd0 || page_type == 2'd3) && encoding == 4'd0;


    // Data page information sent through arbiter fifo to output arbiter
    logic [3:0] arbiter_switch;
    assign arbiter_switch = {page_data_rledict_8, page_data_rledict_4, page_data_rle_1, plain_page};

    // Input select for input arbiter
    logic [3:0] input_select_oh;
    assign input_select_oh[0] = page_data_rle_1;                                                                   // -> rle
    assign input_select_oh[1] = page_dict_plain_4 | page_data_rledict_4;                                           // -> dict_4
    assign input_select_oh[2] = page_dict_plain_8 | page_data_rledict_8;                                           // -> dict_8
    // Default to plain when all switches are off
    assign input_select_oh[3] = plain_page;                                                                  // -> plain


    logic [3:0] input_select_ff;
    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input_select_ff <= 4'b1000; // default plain route (bypass)
    end else if (first_beat_comb) begin
        input_select_ff <= input_select_oh;
    end else if (beat_accepted && in_stream_ff.tlast) begin
        input_select_ff <= 4'b1000; // optional: clear to default after packet
    end
    end

    // Active selection: before SOP use combinational decode, inside packet use latched route
    wire [3:0] input_select_comb = inside_pkt_ff ? input_select_ff : input_select_oh;



    logic ready_for_input;

    AXI4SC rle_in(clk);
    AXI4SC rle_out(clk);
    assign rle_in.tdata = in_stream_ff.tdata;
    assign rle_in.tconfig = in_stream_ff.tconfig;
    assign rle_in.tkeep = in_stream_ff.tkeep;
    assign rle_in.tlast = in_stream_ff.tlast;
    assign rle_in.tvalid = (ready_for_input) ? in_stream_ff.tvalid && input_select_comb[0] : 1'b0;

    AXI4SC dict_4_in(clk);
    AXI4SC dict_4_out(clk);
    assign dict_4_in.tdata = in_stream_ff.tdata;
    assign dict_4_in.tconfig = in_stream_ff.tconfig;
    assign dict_4_in.tkeep = in_stream_ff.tkeep;
    assign dict_4_in.tlast = in_stream_ff.tlast;
    assign dict_4_in.tvalid = (ready_for_input) ? in_stream_ff.tvalid && input_select_comb[1] : 1'b0;

    AXI4SC dict_8_in(clk);
    AXI4SC dict_8_out(clk);
    assign dict_8_in.tdata = in_stream_ff.tdata;
    assign dict_8_in.tconfig = in_stream_ff.tconfig;
    assign dict_8_in.tkeep = in_stream_ff.tkeep;
    assign dict_8_in.tlast = in_stream_ff.tlast;
    assign dict_8_in.tvalid = (ready_for_input) ? in_stream_ff.tvalid && input_select_comb[2] : 1'b0;

    AXI4SC bypass_in(clk);
    AXI4SC bypass_out(clk);
    assign bypass_in.tdata = in_stream_ff.tdata;
    assign bypass_in.tconfig = in_stream_ff.tconfig;
    assign bypass_in.tkeep = in_stream_ff.tkeep;
    assign bypass_in.tlast = in_stream_ff.tlast;
    assign bypass_in.tvalid = (ready_for_input) ? in_stream_ff.tvalid && input_select_comb[3] : 1'b0;

    assign ready_for_input =
        (input_select_comb[0] & rle_in.tready)
    | (input_select_comb[1] & dict_4_in.tready)
    | (input_select_comb[2] & dict_8_in.tready)
    | (input_select_comb[3] & bypass_in.tready);



    // Input to output arbiter fifo
    localparam int ARBITER_FIFO_DEPTH = 4; 
    logic        arbiter_push_ready, arbiter_head_valid;
    logic [3:0]  arbiter_head;

    // Drive upstream ready
    assign in_stream_ff.tready = ready_for_input && arbiter_push_ready;

    logic arbiter_pop;
    arbiter_fifo #(.W(4), .DEPTH(ARBITER_FIFO_DEPTH)) arbiter_fifo (
    .clk        (clk),
    .rst        (!rst_n),                // active-high reset
    .push_valid (first_beat_comb && |arbiter_switch),  // push on SOP
    .push_data  (arbiter_switch),
    .push_ready (arbiter_push_ready),
    .pop        (arbiter_pop),
    .head_data  (arbiter_head),
    .head_valid (arbiter_head_valid)
    );

    //Output arbiter
    assign arbiter_pop = out_stream.tvalid && out_stream.tready && out_stream.tlast;


    logic [3:0] output_select_comb;
    assign output_select_comb[0] = arbiter_head[1];                                           // -> rle
    assign output_select_comb[1] = arbiter_head[2];                                           // -> dict_4 (no dict pages)
    assign output_select_comb[2] = arbiter_head[3];                                           // -> dict_8 (no dict pages)
    // Default to plain when all switches are off
    assign output_select_comb[3] = arbiter_head[0];                                            // -> plain



    logic out_inside_pkt_ff;
    wire out_beat_acc = out_stream.tvalid && out_stream.tready;

    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_inside_pkt_ff <= 1'b0;
    end else if (out_beat_acc) begin
        if (!out_inside_pkt_ff) begin
        // First accepted beat (SOP): be inside the packet only if not last
        out_inside_pkt_ff <= ~out_stream.tlast;
        end else begin
        // Inside packet: drop to 0 when the last beat is accepted
        if (out_stream.tlast) out_inside_pkt_ff <= 1'b0;
        end
    end
    end

    wire out_first_beat_comb = out_beat_acc && !out_inside_pkt_ff;



    logic [3:0] output_select_ff;
    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_select_ff <= 4'b1000; // default plain route (bypass)
    end else if (out_first_beat_comb) begin
        output_select_ff <= output_select_comb;
    end else if (out_beat_acc && out_stream.tlast) begin
        output_select_ff <= 4'b1000; // optional: clear to default after packet
    end
    end

    // Active selection: before SOP use combinational decode, inside packet use latched route
    wire [3:0] output_select_oh = out_inside_pkt_ff ? output_select_ff : output_select_comb;




    // ---------- Mux valids/data/keep/last/config ----------
    assign out_stream.tvalid =
        (output_select_oh[0] && rle_out.tvalid)     ||
        (output_select_oh[1] && dict_4_out.tvalid)  ||
        (output_select_oh[2] && dict_8_out.tvalid)  ||
        (output_select_oh[3] && bypass_out.tvalid);

    assign out_stream.tdata   = output_select_oh[0] ? rle_out.tdata    :
                                output_select_oh[1] ? dict_4_out.tdata :
                                output_select_oh[2] ? dict_8_out.tdata :
                                                bypass_out.tdata;

    assign out_stream.tkeep   = output_select_oh[0] ? rle_out.tkeep    :
                                output_select_oh[1] ? dict_4_out.tkeep :
                                output_select_oh[2] ? dict_8_out.tkeep :
                                                bypass_out.tkeep;

    assign out_stream.tlast   = output_select_oh[0] ? rle_out.tlast    :
                                output_select_oh[1] ? dict_4_out.tlast :
                                output_select_oh[2] ? dict_8_out.tlast :
                                                bypass_out.tlast;

    assign out_stream.tconfig = output_select_oh[0] ? rle_out.tconfig  :
                                output_select_oh[1] ? dict_4_out.tconfig :
                                output_select_oh[2] ? dict_8_out.tconfig :
                                                bypass_out.tconfig;

    // ---------- Backpressure to the selected egress only ----------
    assign rle_out.tready    = out_stream.tready && output_select_oh[0];
    assign dict_4_out.tready = out_stream.tready && output_select_oh[1];
    assign dict_8_out.tready = out_stream.tready && output_select_oh[2];
    assign bypass_out.tready = out_stream.tready && output_select_oh[3];

    // Map internal narrow counter to 64-bit output for CSR readback
    assign pages_done_count = {56'd0, pages_done_counter};




    reader_rle reader_rle (
        .clk(clk),
        .rst_n(rst_n),
        .axis_host_recv(rle_in),
        .axis_host_send(rle_out),
    );

    reader_dict #(
        .OUT_BYTE_WIDTH(4)
    ) reader_dict_4 (
        .clk(clk),
        .rst_n(rst_n),
        .axis_host_recv(dict_4_in),
        .axis_host_send(dict_4_out),
    );

    reader_dict #(
        .OUT_BYTE_WIDTH(8)
    ) reader_dict_8 (
        .clk(clk),
        .rst_n(rst_n),
        .axis_host_recv(dict_8_in),
        .axis_host_send(dict_8_out),
    );

    OverflowRegister plain_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in(bypass_in),
        .out(bypass_out)
    );
endmodule
