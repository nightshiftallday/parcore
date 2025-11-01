`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;
import libstf::data8_t;
import libstf::data32_t;

// NOTE: this module expects the offset to be non-zero.

module StripLevels #(
  parameter NUM_ELEMENTS = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ndata_i.s in, // #(data8_t, NUM_ELEMENTS)
    ndata_i.m out // #(data8_t, NUM_ELEMENTS)
);

data8_t[NUM_ELEMENTS * 2 - 1:0] keep_data;
logic[NUM_ELEMENTS * 2 - 1:0] keep_keep;
// data8_t[1:0] keep_last;
data32_t keep_offset;
logic keep_second_half_valid;
logic keep_received_last;

// In general, we could define a first and second half of the buffered data
// as follows:
//
// data8t first_keep_data[NUM_ELEMENTS - 1:0] = keep_data[NUM_ELEMENTS - 1:0]
// data8t second_keep_data[NUM_ELEMENTS - 1:0] = keep_data[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS]

typedef enum logic {
    ST_IDLE,
    ST_CONF
} state_t;
state_t state;

// The actual offset used to compute the output. The input offset can be
// a 32bit integer, meaning we may need to skip everal databeats of input.
// We are not out.ready until the keep_offset is below NUM_ELEMENTS (and thus
// we have reached the databeat where we stop discarding parts of its data).
logic [5:0] offset;
data8_t[NUM_ELEMENTS * 2 - 1:0] data;
logic[NUM_ELEMENTS * 2 - 1:0] keep;
// data8_t[1:0] last;
logic second_half_valid;
logic more_to_keep;
logic received_last;

// Driving internal state and necessary buffering for the input
always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        state <= ST_IDLE;
        keep_offset <= 0;
        keep_data <= '0;
        keep_keep <= '0;
        // keep_last <= '0;
        keep_second_half_valid <= 0;
        keep_received_last <= 0;
    end else begin
        case (state) 
            ST_IDLE: begin
              if (in.ready && in.valid && ~out.last) begin
                  $display("in idle, got databeat in. offset: %d, keep: %x", offset, out.keep);
                  keep_offset <= in.data[3:0] + 4;
                  keep_data[NUM_ELEMENTS - 1:0] <= in.data;
                  keep_keep[NUM_ELEMENTS - 1:0] <= in.keep;
                  // keep_last[0] <= in.last;
                  keep_second_half_valid <= 0;
                  keep_received_last <= in.last;
              end
            end

            ST_CONF: begin
                $display("in conf. offset: %d, keep: %x", offset, out.keep);
                keep_received_last <= received_last | in.last;

                // If we're over the offset, we keep taking in input and decrement
                // the offset until we get an offset that's in the current
                // first databeat.
                if (in.ready && in.valid) begin
                    if (keep_offset >= NUM_ELEMENTS) begin
                        keep_offset <= keep_offset - NUM_ELEMENTS;
                    end
                end

                if (out.ready && out.valid) begin
                    if (out.last) begin
                        // Reset to default state
                        state <= ST_IDLE;
                        keep_offset <= 0;
                        keep_data <= '0;
                        keep_keep <= '0;
                        // keep_last <= 0;
                        keep_second_half_valid <= 0;
                        keep_received_last <= 0;
                    end else begin
                        // Swap previous 2nd input for 1st
                        keep_data[NUM_ELEMENTS - 1:0] <= data[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS];
                        keep_keep[NUM_ELEMENTS - 1:0] <= keep[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS];
                        // keep_last[0] <= last[1];

                        keep_data[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] <= '0;
                        keep_keep[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] <= '0;
                        // keep_last[1] <= 0;

                        keep_second_half_valid <= 0;
                    end
                end else if (in.ready && in.valid) begin
                    // If we received input in this cycle but didn't output
                    // any, we need to buffer to the second half of data.
                    keep_data[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] <= in.data;
                    keep_keep[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] <= in.keep;
                    keep_data[1] <= in.last;

                    keep_second_half_valid <= 1;
                end
            end
        endcase
    end
end

// Driving the input and handling combinatorial state
always_comb begin
    case (state)
      ST_IDLE: begin
            in.ready = 1;
            if (in.ready && in.valid) begin
                data[NUM_ELEMENTS - 1:0] = in.data;
                data[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] = '0;

                keep[NUM_ELEMENTS - 1:0] = in.keep;
                keep[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] = '0;

                // last[0] = in.last;
                // last[1] = 0;

                offset = in.data[3:0] + 4;
                received_last = in.last;
            end
        end

        ST_CONF: begin
            // We can read input if:
            // - we don't have buffered data to send out still
            // - we may have buffered data, but it's okay since we're putting
            //   it out this cycle.
            // - we have an offset that spans beyond the current first
            // databeat, so we need to read more.
            in.ready = ~keep_received_last && (~keep_second_half_valid || out.valid && out.ready || keep_offset >= NUM_ELEMENTS);

            data[NUM_ELEMENTS - 1:0]                = keep_data[NUM_ELEMENTS - 1:0];
            data[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] = (in.ready && in.valid) ? in.data : keep_data[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS];

            keep[NUM_ELEMENTS - 1:0]                = keep_keep[NUM_ELEMENTS - 1:0];
            keep[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS] = (in.ready && in.valid) ? in.keep : keep_keep[NUM_ELEMENTS * 2 - 1:NUM_ELEMENTS];

            // last[0] = keep_last[0];
            // last[1] = (in.ready && in.valid) ? in.last : keep_last[1];

            offset = keep_offset[5:0];
            received_last = keep_received_last;
        end
    endcase

    second_half_valid = keep_second_half_valid || (state == ST_CONF && in.ready && in.valid);
end

// Setting the output state
always_comb begin
    // more_to_keep = | (keep[offset + NUM_ELEMENTS - 1:NUM_ELEMENTS * 2 -1]);
    more_to_keep = |(keep >> (offset + NUM_ELEMENTS));
    out.valid = keep_offset < NUM_ELEMENTS && (second_half_valid || (~more_to_keep && received_last));

    for(int i = 0; i < NUM_ELEMENTS; i++) begin
        out.data[i] = data[offset + i];
    end

    for(int i = 0; i < NUM_ELEMENTS; i++) begin
        out.keep[i] = keep[offset + i];
    end

    // out.last = last[0] || ~more_to_keep;
    out.last = ~more_to_keep;
end

endmodule
