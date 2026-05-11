`timescale 1ns / 1ps

/**
 * ReadyValidCyclicDriver drives a ready valid signal forever with a constant
 * list of data values. Values are outputted in the provided order, from first
 * to last. When the last element is transmitted the driver resets and
 * restarts sending from the first element.
 */
module ReadyValidCyclicDriver #(
    parameter type data_t,
    parameter NUM_ELEMENTS
) (
    input logic clk,
    input logic rst_n,

    input data_t data[NUM_ELEMENTS - 1:0],

    ready_valid_i.m out_data
);

logic reset_synced = 1'b0;

initial begin
    reset_synced = 1'b0;
    wait(rst_n == 1'b1);
    fork
        begin
            int rand_delay;
            std::randomize(rand_delay) with {
                rand_delay < 100;
                rand_delay > 40;
            };
            #(rand_delay * 1ns);
            reset_synced = 1'b1;
        end
    join_none
end

reg [$clog2(NUM_ELEMENTS)-1:0] i = 0;

// We always have data to put out, as we're cycling through the input values
assign out_data.data = data[i];
assign out_data.valid = reset_synced;

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        i <= 0;
    end else if (out_data.ready) begin
        i <= (i + 1) % NUM_ELEMENTS;
    end
end

endmodule
