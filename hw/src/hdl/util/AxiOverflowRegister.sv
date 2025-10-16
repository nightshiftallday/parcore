`timescale 1ns / 1ps

import lynxTypes::*;
import reader_pkg::*;

module OverflowRegister (
    input  logic                       clk,
    input  logic                       rst_n,

    AXI4SC.s in, 
    AXI4SC.m out

);
    // state
    typedef struct packed {
        logic [AXI_DATA_BITS-1:0]       data, ov_data;
        logic [CONFIG_WIDTH-1:0]        cfg,  ov_cfg;
        logic [AXI_DATA_BITS/8-1:0]     keep, ov_keep;
        logic                           last, ov_last;
        logic                           valid, ov_valid;
    } st_t;

    st_t s = '{default: '0};
    st_t ns = '{default: '0};
    wire take_in   = (~s.ov_valid) || (~s.valid);

    // Combinational next-state
    always_comb begin
        ns = s;                            // hold by default

        if (take_in) begin
            ns.data  = in.tdata;
            ns.cfg   = in.tconfig;
            ns.keep  = in.tkeep;
            ns.last  = in.tlast;
            ns.valid = in.tvalid;
        end

        // Clear overflow first (highest priority)
        if (out.tready && s.ov_valid) begin
            ns.ov_valid = 1'b0;
        end
        // Else capture overflow exactly once when needed
        else if (!out.tready && s.valid && !s.ov_valid) begin
            ns.ov_data  = s.data;
            ns.ov_cfg   = s.cfg;
            ns.ov_keep  = s.keep;
            ns.ov_last  = s.last;
            ns.ov_valid = 1'b1;
        end
    end

    // Registers
    always_ff @(posedge clk) begin
        if (rst_n == 1'b0) begin 
            s.ov_valid <= 1'b0;
            s.valid <= 1'b0;
        end
        else
            s <= ns;
    end

    assign in.tready   = rst_n && ((~s.ov_valid) || (~s.valid));
    assign out.tdata   = s.ov_valid ? s.ov_data  : s.data;
    assign out.tconfig = s.ov_valid ? s.ov_cfg   : s.cfg;
    assign out.tkeep   = s.ov_valid ? s.ov_keep  : s.keep;
    assign out.tlast   = s.ov_valid ? s.ov_last  : s.last;
    assign out.tvalid  = s.valid || s.ov_valid;

endmodule
