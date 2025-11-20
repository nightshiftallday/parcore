`timescale 1ns / 1ps

// This is an interface to synchronize an auxiliary metadata interface with a
// main data stream. The ready port on this interface (unintuitively) should
// be used to govern the ready signal on the main data interface paired with
// this.
interface hold_data_i #(
    parameter type data_t
);
    data_t data;
    // When the data the interface is holding is valid
    logic  valid;
    // When we're ready to take more input on the actual interface
    logic  ready;

    modport m (
        output data, ready, valid
    );

    modport s (
        input  data, ready, valid
    );
endinterface

module HoldForward #(
  parameter type data_t
) (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_data, // #(data_t)
    ready_valid_i.m out_data, // #(data_t)

    // When to pause the metadata ready value, signaling that no more input
    // should be taken associated with this metadata.
    input logic pause,
    // When to drop the metadata we're currently holding
    input logic drop,

    hold_data_i.m data // #(data_t)
);

// Read input ready valid interface as data_t
data_t in_data_data;
assign in_data_data = in_data.data;

// Register to buffer metadata after it has been configured
data_t keep_meta;

typedef enum logic [1:0] {
    ST_IDLE,
    ST_CONF,
    ST_FLUSH
} state_t;

typedef enum logic {
    ST_UNSENT,
    ST_SENT
} sent_t;

sent_t sent;
state_t state;

logic paused;

// Reading in, preserving state logic
always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        state <= ST_IDLE;
        paused <= 0;
    end else begin
        case (state)
            ST_IDLE: begin
                // We want to transition into the buffering ST_CONF state only
                // if this is not both the first and last databeat for this
                // transfer.
                //
                // If that's the case, the metadata is still valid and we put it
                // out, but we don't want to buffer any data.
                if (in_data.valid && in_data.ready && ~drop) begin
                    keep_meta <= in_data_data;
                    state <= ST_CONF;
                    paused <= paused || pause;
                end
            end

            ST_CONF: begin
                paused <= paused || pause;

                if (drop) begin
                    // If we've propagated the databeat on the output interface
                    // or we're going to do it in this cycle, then we can reset
                    // to the idle state to take in more input.
                    if (sent == ST_SENT || out_data.ready) begin
                        state <= ST_IDLE;
                        paused <= 0;
                    end else begin
                        state <= ST_FLUSH;
                    end
                end
            end

            ST_FLUSH: begin
                // When we do send the databeat out, we can reset to the ST_IDLE 
                // state and take more input.
                if (out_data.valid && out_data.ready) begin
                    state <= ST_IDLE;
                    paused <= 0;
                end
            end
        endcase
    end
end

// Output meta interface should reflect internal state
always_comb begin
    case (state)
        ST_IDLE: begin
            data.valid = rst_n && in_data.valid;
            // As long as we can take in more metadata we can get data
            // associated with that meta, so the meta stream is ready.
            data.ready = in_data.ready;
            data.data = in_data_data;
            
            // We're not buffering any data currently, so we're ready to take
            // in new data.
            //
            // There's one edge case. If we need to drop the value in the same
            // cycle, the output must be ready to take the meta input.
            // So either:
            // 1. We're not dropping.
            // 2. We're dropping and the output is ready.
            in_data.ready = rst_n && (~drop || (drop && out_data.ready));
        end

        ST_CONF: begin
            data.valid = 1'b1;
            data.ready = ~paused;
            data.data = keep_meta;

            in_data.ready = 1'b0;
        end

        ST_FLUSH: begin
            data.valid = 1'b0;
            data.ready = 1'b0;

            in_data.ready = 1'b0;
        end
    endcase
end

// Propagating metadata forward, only one databeat
always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        sent <= ST_UNSENT;
    end else begin
        case (sent)
            ST_UNSENT: begin
                // We only want to move to the ST_SENT state if we did send the
                // meta databeat out AND we're not dropping the current config
                // immediately.
                //
                // We also don't want to transition to ST_UNSET when we're
                // waiting for a flush, as we're immediately transitioning to
                // the next meta, so we want to reset to a ST_UNSET state.
                if (out_data.valid && out_data.ready && ~drop && state != ST_FLUSH) begin
                    sent <= ST_SENT;
                end
            end

            ST_SENT: begin
                if (drop) begin
                    sent <= ST_UNSENT;
                end
            end
        endcase
    end
end

// We can write the new metadata to the next stage when the metadata we hold
// is valid and we haven't sent a databeat for this configuration already.
assign out_data.valid = (data.valid || state == ST_FLUSH) && sent == ST_UNSENT;
assign out_data.data = data.data;

endmodule
