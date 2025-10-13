`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module BarrelShifter #(
    parameter WIDTH = 512,
    parameter REGISTER_LEVELS = 0,
    parameter BYTES = WIDTH / 8,
    parameter OFFSET_WIDTH = $clog2(BYTES)
) (
    input logic aclk,
    input logic aresetn,

    input logic[OFFSET_WIDTH - 1:0] i_offset,

    AXI4SC.s i_data,
    AXI4SC.m o_data
);

localparam int PIPELINE_STAGES = $clog2(BYTES) + 1;
localparam int REGISTER_GAP = (REGISTER_LEVELS == 0 ? PIPELINE_STAGES + 2 : PIPELINE_STAGES / REGISTER_LEVELS);

AXI4SC axis_stages[PIPELINE_STAGES](.aclk(aclk));
logic[OFFSET_WIDTH - 1:0] offset_stages[PIPELINE_STAGES];

// Input assignments
`AXIS_ASSIGN(i_data, axis_stages[0])
assign offset_stages[0] = i_offset;

// Generate pipeline stages
for (genvar i = 0; i < PIPELINE_STAGES - 1; i++) begin
    ConstantShifter #(.SHIFT_INDEX(i), .WIDTH(WIDTH), .REGISTER(((i + 1) % REGISTER_GAP) == 0)) inst_shifter (
        .aclk(aclk),
        .aresetn(aresetn),

        .i_data(axis_stages[i]),
        .i_offset(offset_stages[i]),

        .o_data(axis_stages[i + 1]),
        .o_offset(offset_stages[i + 1])
    );
end

// Output assignment
`AXIS_ASSIGN(axis_stages[PIPELINE_STAGES - 1], o_data)

endmodule
