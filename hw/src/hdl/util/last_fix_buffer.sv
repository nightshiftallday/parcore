`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;

module axi_stream_tlast_fix #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  aclk,
    input  wire                  aresetn,

    AXI4SC.s  in,
    AXI4SC.m out

);

    // First stage: hold incoming data
    reg [DATA_WIDTH-1:0] buffer_data;
    reg [KEEP_WIDTH-1:0] buffer_keep;
    reg                  buffer_last;
    reg                  buffer_valid;

    // Second stage: hold lookahead
    reg [DATA_WIDTH-1:0] next_data;
    reg [KEEP_WIDTH-1:0] next_keep;
    reg                  next_last;
    reg                  next_valid;

    wire input_ready = ~next_valid;
    assign in.tready = input_ready;

    wire next_is_dummy_last = next_valid && (next_keep == {KEEP_WIDTH{1'b0}}) && next_last;

    // FSM logic
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            buffer_valid <= 0;
            next_valid   <= 0;
            out.tvalid <= 0;
        end else begin
            // Stage 1: load new beat into next_valid buffer
            if (in.tvalid && input_ready) begin
                next_data  <= in.tdata;
                next_keep  <= in.tkeep;
                next_last  <= in.tlast;
                next_valid <= 1;
            end

            // When buffer is empty and next_valid has data, promote to buffer
            if (~buffer_valid && next_valid) begin
                buffer_data  <= next_data;
                buffer_keep  <= next_keep;
                buffer_last  <= next_last;
                buffer_valid <= 1;
                next_valid   <= 0;
            end else if (buffer_valid && next_valid && next_is_dummy_last) begin
                // Merge dummy TLAST into buffer
                buffer_last  <= 1;
                buffer_valid <= 1;
                next_valid   <= 0;
            end

            // Output stage
            if (out.tvalid && out.tready) begin
                out.tvalid <= 0;
            end

            if (~out.tvalid && buffer_valid) begin
                out.tdata  <= buffer_data;
                out.tkeep  <= buffer_keep;
                out.tlast  <= buffer_last;
                out.tvalid <= 1;
                buffer_valid  <= 0;
            end
        end
    end
endmodule
