`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;
import reader_pkg::*;

module decompressor #(
    parameter ADDITIONAL_RESET_CYCLES = 0
)(
    input logic clk,
    input logic rst_n,

    // Data Interfaces
    AXI4SC.s  in_stream,
    AXI4SC.m out_stream
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

    logic [2:0] compression_mode;
    assign compression_mode = input_config[COMPRESSION_CONFIG_INDEX+2:COMPRESSION_CONFIG_INDEX];
    // Input select for input arbiter


    logic [2:0] compression_mode_ff;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compression_mode_ff <= 'b000; // default plain route (bypass)
        end else if (first_beat_comb) begin
            compression_mode_ff <= compression_mode;
        end else if (beat_accepted && in_stream_ff.tlast) begin
            compression_mode_ff <= 'b000; // optional: clear to default after packet
        end
    end

    // Active selection: before SOP use combinational decode, inside packet use latched route
    wire [2:0] compression_mode_comb = inside_pkt_ff ? compression_mode_ff : compression_mode;

    logic ready_for_input;
    reg decompressor_input_paused;

    AXI4SC decompressor_in(clk);
    AXI4SC decompressor_out(clk);
    assign decompressor_in.tdata = in_stream_ff.tdata;
    assign decompressor_in.tconfig = in_stream_ff.tconfig;
    assign decompressor_in.tkeep = in_stream_ff.tkeep;
    assign decompressor_in.tlast = in_stream_ff.tlast;
    assign decompressor_in.tvalid = (ready_for_input) ? in_stream_ff.tvalid && compression_mode_comb == 3'd1 : 1'b0;


    // Debug decompressor simulator
    AXI4SC simulator_in(clk);
    AXI4SC simulator_out(clk);
    assign simulator_in.tdata = in_stream_ff.tdata;
    assign simulator_in.tconfig = in_stream_ff.tconfig;
    assign simulator_in.tkeep = in_stream_ff.tkeep;
    assign simulator_in.tlast = in_stream_ff.tlast;
    assign simulator_in.tvalid = (ready_for_input) ? in_stream_ff.tvalid && compression_mode_comb == 3'd2 : 1'b0;


    AXI4SC bypass_in(clk);
    AXI4SC bypass_out(clk);
    assign bypass_in.tdata = in_stream_ff.tdata;
    assign bypass_in.tconfig = in_stream_ff.tconfig;
    assign bypass_in.tkeep = in_stream_ff.tkeep;
    assign bypass_in.tlast = in_stream_ff.tlast;
    assign bypass_in.tvalid = (ready_for_input) ? in_stream_ff.tvalid && compression_mode_comb == 3'd0 : 1'b0;

    // Input arbiter handles
    logic arbiter_push_ready, arbiter_head_valid;

    assign ready_for_input = arbiter_push_ready &&
        ((compression_mode_comb == 3'd1 & decompressor_in.tready && !decompressor_input_paused)
    | (compression_mode_comb == 3'd0 & bypass_in.tready)
    | (compression_mode_comb == 3'd2 & simulator_in.tready));

    // Drive upstream ready
    assign in_stream_ff.tready = ready_for_input;



    // Input to output arbiter fifo
    localparam int ARBITER_FIFO_DEPTH = 8; 
    logic [CONFIG_WIDTH-1:0]  arbiter_head;

    logic arbiter_pop;
    arbiter_fifo #(.W(CONFIG_WIDTH), .DEPTH(ARBITER_FIFO_DEPTH)) arbiter_fifo (
    .clk        (clk),
    .rst        (!rst_n),                // active-high reset
    .push_valid (first_beat_comb),       // push on SOP
    .push_data  (input_config),
    .push_ready (arbiter_push_ready),
    .pop        (arbiter_pop),
    .head_data  (arbiter_head),
    .head_valid (arbiter_head_valid)
    );

    //Output arbiter
    assign arbiter_pop = out_stream.tvalid && out_stream.tready && out_stream.tlast;


    logic [2:0] output_select_comb;
    assign output_select_comb[0] = arbiter_head[COMPRESSION_CONFIG_INDEX+2:COMPRESSION_CONFIG_INDEX] == 3'b000;    // -> bypass
    assign output_select_comb[1] = arbiter_head[COMPRESSION_CONFIG_INDEX+2:COMPRESSION_CONFIG_INDEX] == 3'b001;    // -> decompressor
    assign output_select_comb[2] = arbiter_head[COMPRESSION_CONFIG_INDEX+2:COMPRESSION_CONFIG_INDEX] == 3'b010;    // -> simulator



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



    logic [2:0] output_select_ff;
    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_select_ff <= 2'b00; // default plain route (bypass)
    end else if (out_first_beat_comb) begin
        output_select_ff <= output_select_comb;
    end else if (out_beat_acc && out_stream.tlast) begin
        output_select_ff <= 2'b00; // optional: clear to default after packet
    end
    end

    // Active selection: before SOP use combinational decode, inside packet use latched route
    wire [2:0] output_select_oh = out_inside_pkt_ff ? output_select_ff : output_select_comb;



    // ---------- Mux valids/data/keep/last/config ----------
    assign out_stream.tvalid = arbiter_head_valid && (  // Only valid when there is a valid output selection
        (output_select_oh[0] && bypass_out.tvalid)     ||
        (output_select_oh[1] && decompressor_out.tvalid) ||
        (output_select_oh[2] && simulator_out.tvalid)
    );

    assign out_stream.tdata   = arbiter_head_valid ? (output_select_oh[0] ? bypass_out.tdata    :
                                output_select_oh[1] ? decompressor_out.tdata :
                                output_select_oh[2] ? simulator_out.tdata :
                                                bypass_out.tdata) : '0;

    assign out_stream.tkeep   = arbiter_head_valid ? (output_select_oh[0] ? bypass_out.tkeep    :
                                output_select_oh[1] ? decompressor_out.tkeep :
                                output_select_oh[2] ? simulator_out.tkeep :
                                                bypass_out.tkeep) : '0;

    assign out_stream.tlast   = arbiter_head_valid ? (output_select_oh[0] ? bypass_out.tlast    :
                                output_select_oh[1] ? decompressor_out.tlast :
                                output_select_oh[2] ? simulator_out.tlast :
                                                bypass_out.tlast) : '0;

    assign out_stream.tconfig = arbiter_head_valid ? arbiter_head : '0;

    // ---------- Backpressure to the selected egress only ----------
    assign bypass_out.tready = out_stream.tready && output_select_oh[0] && arbiter_head_valid;
    assign decompressor_out.tready = out_stream.tready && output_select_oh[1] && arbiter_head_valid;
    assign simulator_out.tready = out_stream.tready && output_select_oh[2] && arbiter_head_valid;


    // Decompressor input paused and reset logic
    reg [1:0] decompressor_reset_counter;
    always_ff @(posedge clk ) begin
    if (!rst_n) begin
        decompressor_input_paused <= 1'b0;
        decompressor_reset_counter <= 0;
    end else begin
        if (decompressor_in.tready && decompressor_in.tvalid && decompressor_in.tlast) begin
            decompressor_input_paused <= 1'b1;
        end else if (decompressor_input_paused && decompressor_out.tready && decompressor_out.tvalid && decompressor_out.tlast) begin
            decompressor_reset_counter <= 2'd2;
        end else if (decompressor_input_paused && decompressor_reset_counter > 0) begin
            if (decompressor_reset_counter == 2'd1) begin
                decompressor_input_paused <= 1'b0;
            end
            decompressor_reset_counter <= decompressor_reset_counter - 1;
        end
    end
    end


    // Snappy decompressor
    // Decompressor simulator debug set up
    AXI4SC decomp_intermediate(clk);
    OverflowRegister decompressor_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in(simulator_in),
        .out(decomp_intermediate)
    );
    decompressor_simulator decompressor_simulator (
        .clk(clk),
        .rst_n(rst_n),

        .in(decomp_intermediate),
        .out(simulator_out)
    );

    // Real Snappydecompressor
    vhsnunzip_wrapper snappy_decompressor (
        .clk(clk),
        .rst_n(rst_n && decompressor_reset_counter == 3'd0),

        .in(decompressor_in),
        .out(decompressor_out)
    );


    // Bypass fifo
    OverflowRegister bypass_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in(bypass_in),
        .out(bypass_out)
    );

    // Stage1 ILA - monitors decompressor input/output streams and internal state
    // ila_stage ila_stage1_inst (
    //     .clk(clk),

    //     // Stage1 input stream
    //     .probe0(in_stream_ff.tdata),
    //     .probe1(in_stream_ff.tvalid),
    //     .probe2(in_stream_ff.tready),
    //     .probe3(in_stream_ff.tlast),
    //     .probe4(in_stream_ff.tconfig),

    //     // Stage1 output stream
    //     .probe5(out_stream.tdata),
    //     .probe6(out_stream.tvalid),
    //     .probe7(out_stream.tready),
    //     .probe8(out_stream.tlast),
    //     .probe9(out_stream.tconfig),

    //     // Stage1 internal state
    //     // Input arbiter select (pad 4-bit to 5-bit with zeros)
    //     .probe10({decompressor_input_paused, compression_mode_comb}),
    //     // Output arbiter select (pad 2-bit to 4-bit)
    //     .probe11({decompressor_reset_counter, output_select_oh}),
    //     // Arbiter head valid
    //     .probe12(arbiter_head_valid)

    // );

endmodule
