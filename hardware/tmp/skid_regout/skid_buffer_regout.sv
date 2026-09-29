`timescale 1ns / 1ps

// Drop-in replacement for SkidBuffer in libstf/hardware/src/hdl/util/skid_buffer.sv whose outputs
// come straight from flip-flops. The mux between the incoming beat and the parked one sits in
// front of the output register, and in.ready only depends on the skid register, so the buffer
// cuts the combinational path in both directions. Same latency (1 cycle), throughput (1 beat per
// cycle) and storage (2 beats) as the original.
module SkidBuffer #(
    parameter type data_t
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in, // #(data_t)
    ready_valid_i.m out // #(data_t)
);

data_t skid_data;
logic  skid_valid;

assign in.ready = !skid_valid;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        out.valid  <= 1'b0;
        skid_valid <= 1'b0;
    end else if (!out.valid || out.ready) begin
        out.valid  <= skid_valid || in.valid;
        skid_valid <= 1'b0;
    end else if (in.valid && in.ready) begin
        // The output is stalled, so the beat accepted in this cycle is parked.
        skid_valid <= 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (!skid_valid)             skid_data <= in.data;
    if (!out.valid || out.ready) out.data  <= skid_valid ? skid_data : in.data;
end

endmodule
