`timescale 1ns / 1ps

import lynxTypes::*;

module AxiStreamRegister (
    input  logic                     clk,
    input  logic                     rst_n,

    AXI4SC.s in, 
    AXI4SC.m out

);
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out.tdata  <= '0;
        out.tkeep  <= '0;
        out.tvalid <= 1'b0;
        out.tlast <= 1'b0;
    end else begin
        if (out.tready || !out.tvalid) begin
            out.tdata  <= in.tdata;
            out.tkeep  <= in.tkeep;
            out.tlast  <= in.tlast;
            out.tvalid <= in.tvalid;
        end 
    end
end

assign in.tready = out.tready || !out.tvalid;


endmodule