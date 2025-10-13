`timescale 1ns / 1ps

import lynxTypes::*;

module ConstantShifter #(
    parameter SHIFT_INDEX,
    parameter WIDTH = 512,
    parameter REGISTER = 0,
    parameter BYTES = WIDTH / 8,
    parameter OFFSET_WIDTH = $clog2(BYTES)
) (
    input logic aclk,
    input logic aresetn,

    AXI4SC.s i_data,
    input logic[OFFSET_WIDTH - 1:0] i_offset,

    AXI4SC.m o_data,
    output logic[OFFSET_WIDTH - 1:0] o_offset
);

// Calculate the shift amount from the bit index
localparam int DATA_SHIFT = 32'd8 << SHIFT_INDEX;
localparam int KEEP_SHIFT = 32'd1 << SHIFT_INDEX;

logic[WIDTH - 1:0] data_shifted;
logic[BYTES - 1:0] keep_shifted;

always_comb begin
    if (i_offset[SHIFT_INDEX] == 1'b1) begin
        data_shifted = {i_data.tdata[WIDTH - DATA_SHIFT - 1:0], i_data.tdata[WIDTH - 1:WIDTH - DATA_SHIFT]};
        keep_shifted = {i_data.tkeep[BYTES - KEEP_SHIFT - 1:0], i_data.tkeep[BYTES - 1:BYTES - KEEP_SHIFT]};
    end else begin
        data_shifted = i_data.tdata;
        keep_shifted = i_data.tkeep;
    end
end

generate if (REGISTER == 1) begin
    always_ff @(posedge aclk) begin
        if (~aresetn == 1'b1) begin
            o_data.tvalid <= 1'b0;
        end else begin
            if (o_data.tready) begin
                o_data.tdata  <= data_shifted;
                o_data.tkeep  <= keep_shifted;
                o_data.tlast  <= i_data.tlast;
                o_data.tvalid <= i_data.tvalid;

                o_offset <= i_offset;
            end
        end
    end
end else begin
    assign o_data.tdata  = data_shifted;
    assign o_data.tkeep  = keep_shifted;
    assign o_data.tlast  = i_data.tlast;
    assign o_data.tvalid = i_data.tvalid;

    assign o_offset = i_offset;
end endgenerate

assign i_data.tready = o_data.tready;

endmodule
