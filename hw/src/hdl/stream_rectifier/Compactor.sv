`timescale 1ns / 1ps

module Compactor #(
    parameter WIDTH = 512,
    parameter CELL_WIDTH = 32,
    parameter REGISTER_LEVELS = 8
) (
    input logic aclk,
    input logic aresetn,

    AXI4SC.s i_data,
    AXI4SC.m o_data
);

localparam NUM_CELLS = WIDTH / CELL_WIDTH;
localparam PIPELINE_STAGES = NUM_CELLS + 1;
localparam COUNTER_WIDTH = $clog2(NUM_CELLS);
localparam REGISTER_GAP = (REGISTER_LEVELS == 0 ? PIPELINE_STAGES + 2 : PIPELINE_STAGES / REGISTER_LEVELS);

AXI4SC axis_stages[PIPELINE_STAGES](.aclk(aclk));
logic[COUNTER_WIDTH - 1:0] counter_stages[PIPELINE_STAGES];

// Input assignments
`AXIS_ASSIGN(i_data, axis_stages[0])
assign counter_stages[0] = 0;

// Generate pipeline stages
for (genvar i = 0; i < PIPELINE_STAGES - 1; i++) begin
    CompactorLevel #(.ID(i), .WIDTH(WIDTH), .CELL_WIDTH(CELL_WIDTH), .REGISTER(((i + 1) % REGISTER_GAP) == 0)) inst_compactor_level (
        .aclk(aclk),
        .aresetn(aresetn),

        .i_data(axis_stages[i]),
        .i_counter(counter_stages[i]),

        .o_data(axis_stages[i + 1]),
        .o_counter(counter_stages[i + 1])
    );
end

// Output assignment
`AXIS_ASSIGN(axis_stages[PIPELINE_STAGES - 1], o_data)

endmodule
