`timescale 1ns / 1ps

import lynxTypes::*;


module arbiter_fifo #(
    parameter int W = 16,          // token width
    parameter int DEPTH = 16       // power of two
) (
    input  logic               clk,
    input  logic               rst,

    // Push token at SOP
    input  logic               push_valid,
    input  logic [W-1:0]       push_data,
    output logic               push_ready,

    // Pop token when output packet completes
    input  logic               pop,          // assert for one cycle when TLAST is accepted
    output logic [W-1:0]       head_data,    // current (peek)
    output logic               head_valid

    // (optional) next_head, next_valid ports could be added back if you really want lookahead
);

    localparam int AW = $clog2(DEPTH);
    logic [W-1:0] mem [0:DEPTH-1] = '{default: '0};
    logic [AW-1:0] wr_ptr, rd_ptr;
    logic [AW:0]   count; // 0..DEPTH

    // status
    wire full  = (count == DEPTH);
    wire empty = (count == 0);

    assign push_ready = !full;
    assign head_valid = !empty;

    // safe peek (return 0 when empty)
    assign head_data = mem[rd_ptr];

    // write
    always_ff @(posedge clk) begin
        if (push_valid && push_ready)
            mem[wr_ptr] <= push_data;
    end

    // pointers & count
    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            unique case ({(push_valid && push_ready), (pop && !empty)})
                2'b10: begin
                    wr_ptr <= wr_ptr + 1'b1;
                    count  <= count + 1'b1;
                end
                2'b01: begin
                    rd_ptr <= rd_ptr + 1'b1;
                    count  <= count - 1'b1;
                end
                2'b11: begin
                    // push and pop in same cycle
                    wr_ptr <= wr_ptr + 1'b1;
                    rd_ptr <= rd_ptr + 1'b1;
                    // count unchanged
                end
                default: ; // no op
            endcase
        end
    end

    // Optional: assert properties in sim
    // assert (!(pop && empty));
    // assert (!(push_valid && !push_ready));
endmodule