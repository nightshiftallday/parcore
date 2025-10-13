`timescale 1ns / 1ps

module CompactorLevel #(
    parameter ID,
    parameter WIDTH = 512,
    parameter CELL_WIDTH = 32,
    parameter REGISTER = 0,
    parameter NUM_CELLS = WIDTH / CELL_WIDTH,
    parameter COUNTER_WIDTH = $clog2(NUM_CELLS)
) (
    input logic aclk,
    input logic aresetn,

    AXI4SC.s i_data,
    input logic[COUNTER_WIDTH - 1:0] i_counter,

    AXI4SC.m o_data,
    output logic[COUNTER_WIDTH - 1:0] o_counter
);

localparam CELL_SIZE = CELL_WIDTH / 8;
localparam NUM_BYTES = WIDTH / 8;

logic[WIDTH - 1:0]         next_data;
logic[NUM_BYTES - 1:0]     next_keep;
logic[COUNTER_WIDTH - 1:0] next_counter;

always_comb begin
    next_data = i_data.tdata;
    next_keep = i_data.tkeep;

    for (int i = 0; i < ID; i++) begin
        if (i_data.tkeep[ID * CELL_SIZE] && i == i_counter) begin
            next_data[i * CELL_WIDTH+:CELL_WIDTH] = i_data.tdata[ID * CELL_WIDTH+:CELL_WIDTH];
            next_keep[i * CELL_SIZE+:CELL_SIZE]   = i_data.tkeep[ID * CELL_SIZE+:CELL_SIZE];
        end
    end

    if (i_counter < ID || !i_data.tkeep[ID * CELL_SIZE]) begin
        next_keep[ID * CELL_SIZE+:CELL_SIZE] = 0;
    end
    
    if (i_data.tkeep[ID * CELL_SIZE]) begin
        next_counter = i_counter + 1;
    end else begin
        next_counter = i_counter;
    end
end

generate if (REGISTER) begin
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            o_data.tvalid <= 1'b0;
        end else begin
            if (o_data.tready) begin
                o_data.tdata  <= next_data;
                o_data.tkeep  <= next_keep;
                o_data.tlast  <= i_data.tlast;
                o_data.tvalid <= i_data.tvalid;

                o_counter <= next_counter;
            end
        end
    end
end else begin
    assign o_data.tdata  = next_data;
    assign o_data.tkeep  = next_keep;
    assign o_data.tlast  = i_data.tlast;
    assign o_data.tvalid = i_data.tvalid;

    assign o_counter = next_counter;
end endgenerate

assign i_data.tready = o_data.tready;

endmodule
