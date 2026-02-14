`timescale 1ns / 1ps

`include "libstf_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;
import libstf::data8_t;
import libstf::data32_t;
import parcore::*;

// This module strips the repetition and definition levels from the start of
// a page. NOTE: this module produces transfers with invalid keeps, and should be
// followed by a data compactor.
module StripLevels #(
    parameter NUM_BYTES = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    ndata_i.s in,            // #(data8_t, NUM_BYTES)
    ndata_i.m out            // #(data8_t, NUM_BYTES)
);

`RESET_RESYNC // Reset pipelining

localparam int NUM_BYTES_OFFSET = 4;

ndata_i #(data8_t, NUM_BYTES) in_inner (), out_inner ();

NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_in (
    .clk(clk),
    .rst_n(reset_synced),

    .in(in),
    .out(in_inner)
);

NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_out (
    .clk(clk),
    .rst_n(reset_synced),

    .in(out_inner),
    .out(out)
);

// ------- State machine ---------
typedef enum logic [2:0] {
    ST_WAIT,
    ST_CONSUME,
    ST_PIPE
} state_t;
state_t state;
offset_t offset;

task process_first_databeat();
    offset_t actual_offset;

    actual_offset = NUM_BYTES_OFFSET + in_inner.data[NUM_BYTES_OFFSET - 1:0];

    if (actual_offset >= NUM_BYTES - 1) begin
      offset <= actual_offset;
      state <= ST_CONSUME;
    end else begin
      configure(actual_offset);
    end
endtask

task consume_databeat();
    offset_t next_offset;

    next_offset = offset - NUM_BYTES;

    if (next_offset < NUM_BYTES) begin
        configure(next_offset);
    end else begin
        offset <= next_offset;
    end
endtask

task configure(offset_t offst);
    offset <= offst;
    state <= ST_PIPE;
endtask

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        offset <= '0;
        state <= ST_WAIT;
    end else begin
        case (state)
            ST_WAIT: begin
                if (in_inner.valid) begin
                    process_first_databeat();
                end
            end

            ST_CONSUME: begin
                if (in_inner.valid) begin
                    consume_databeat();
                end
            end

            ST_PIPE: begin
                if (out_inner.ready && out_inner.valid) begin
                    offset <= '0;

                    if (out_inner.last) begin
                        state <= ST_WAIT;
                    end
                end
            end
        endcase
    end
end

// ------- Driving input ---------
assign in_inner.ready = state == ST_CONSUME || (state == ST_PIPE && out_inner.ready);

always_comb begin
    case (state)
        ST_PIPE: begin
            out_inner.data  = in_inner.data;
            out_inner.valid = in_inner.valid;
            out_inner.keep  = in_inner.keep & ({NUM_BYTES{1'b1}} << offset);
            out_inner.last  = in_inner.last;
        end

        default: begin
            out_inner.valid = 1'b0;
        end
    endcase
end

endmodule
