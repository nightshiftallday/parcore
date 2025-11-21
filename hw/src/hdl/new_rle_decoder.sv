`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"
`include "parcore_types.svh"

import lynxTypes::*;
import parcore::*;

module ExpandRLE #(
    parameter type data_t,
    parameter NUM_ELEMENTS
) (
    input logic clk,
    input logic rst_n,

    tagged_i.s in,  // #(data_t, $bits(rle_count_t))
    ndata_i.m out   // #(data_t, NUM_ELEMENTS)
);

// Extracting data from the tagged_i interface
data_t in_data;
rle_count_t in_meta;

assign in_data = in.data;
assign in_meta = in.tag;

typedef enum logic {
    ST_IDLE,
    ST_CONF
} state_t;
state_t state;
data_t keep_element;
rle_count_t keep_count;

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        state <= ST_IDLE;
        keep_element <= 0;
        keep_count <= 0;
    end else begin
        case (state)
            ST_IDLE: begin
                if (in.ready && in.valid) begin
                    // We will immediately output the first batch of
                    // NUM_ELEMENTS in the first cycle that we receive a valid
                    // RLE number to decode, so we want to buffer the state
                    // only if we need to put out more elements than we can do
                    // in a cycle.
                    if (~(out.ready && out.valid && out.last)) begin
                        keep_element <= in_data;
                        // If we have sent a databeat out but it was not last,
                        // decrement the count value.
                        if (out.ready && out.valid) begin
                            keep_count <= in_meta - NUM_ELEMENTS;
                        end else begin
                            keep_count <= in_meta;
                        end

                        state <= ST_CONF;
                    end
                end
            end

            ST_CONF: begin
                if (out.valid && out.ready) begin
                  if (out.last) begin
                      // This is the last batch for this RLE decoding, so
                      // reset to idle state.
                      state <= ST_IDLE;
                      keep_element <= 0;
                      keep_count <= 0;
                  end else begin
                      // If ~out.last, then count (=keep_count) > NUM_ELEMENTS
                      keep_count <= keep_count - NUM_ELEMENTS;
                  end
                end
            end
        endcase
    end
end

// Deriving internal state from input and current buffering state
data_t element;
rle_count_t count;
always_comb begin
    // We need to provide default values to prevent latch inference
    element = '0;

    case (state)
        ST_IDLE: begin
            if (in.ready && in.valid) begin
                element = in_data;
                count = in_meta;
            end else begin
                count = 0;
            end
        end

        ST_CONF: begin
            element = keep_element;
            count = keep_count;
        end
    endcase

    in.ready = state == ST_IDLE && rst_n;
end

// Driving output based on the current intrenal state
always_comb begin
    out.valid = count > 0;
    out.last = count <= NUM_ELEMENTS;
    for (int i = 0; i < NUM_ELEMENTS; i++) begin
        out.data[i] = element;
        out.keep[i] = i < count;
    end
end

endmodule
