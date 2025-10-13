`timescale 1ns / 1ps

import lynxTypes::*;

module decompressor_simulator (
    input  logic        clk,
    input  logic        rst_n,

    AXI4SC.s in,
    AXI4SC.m out
);

    logic [3:0] cycle_cnt;  // counts x ... 0

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt   <= 3'd0;
            out.tdata   <= '0;
            out.tkeep   <= '0;
            out.tlast   <= 1'b0;
            out.tvalid  <= 1'b0;
        end else begin
            // increment counter every cycle

            if (cycle_cnt == 3'd0) begin
                // only every 8th cycle can capture new data
                if (in.tvalid && out.tready) begin
                    out.tdata  <= in.tdata;
                    out.tkeep  <= in.tkeep;
                    out.tlast  <= in.tlast;
                    out.tvalid <= 1'b1;
                end else if (out.tready) begin
                    // clear tvalid if not sending
                    out.tvalid <= 1'b0;
                end
                cycle_cnt <= 4'd10;
            end else begin
                cycle_cnt <= cycle_cnt - 4'd1;

                // during stall cycles, do not accept new data
                if (out.tready)
                    out.tvalid <= 1'b0;
            end
        end
    end

    // upstream only ready on the active cycle
    assign in.tready = (cycle_cnt == 3'd0) && out.tready;

endmodule
