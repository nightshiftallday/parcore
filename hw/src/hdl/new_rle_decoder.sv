`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;

module ExpandRLE #(
    parameter NUM_BITS,
    parameter OUT_BIT_WIDTH = AXI_DATA_BITS,
    parameter NUM_ELEMENTS = OUT_BIT_WIDTH / NUM_BITS
) (
    input logic clk,
    input logic rst_n,

    bitdata_i in, // #(NUM_BITS, rle_count_t)
    ndata_i out   // #(logic[NUM_BITS - 1:0], NUM_ELEMENTS)
);

// Extracting data from the bitdata_i interface
logic[NUM_BITS - 1:0] in_data;
rle_count_t in_meta;

assign in_data = in.data;
assign in_meta = in.meta;

typedef enum logic {
    ST_IDLE,
    ST_CONF
} state_t;
state_t state;
logic[NUM_BITS - 1:0] keep_element;
rle_count_t keep_count;

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        state <= ST_IDLE;
        keep_element <= 0;
        keep_count <= 0;
    end else begin
        case (state)
            ST_IDLE: begin
                if (in.valid && in.ready) begin
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
logic[NUM_BITS - 1:0] element;
rle_count_t count;
always_comb begin
    case (state)
        ST_IDLE: begin
            if (in.valid && in.ready) begin
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
