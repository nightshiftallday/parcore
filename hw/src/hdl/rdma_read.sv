`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "parcore_types.svh"

import libstf::data8_t;
import parcore::*;

module RDMARead #(
    parameter AXI_DATA_BITS = 512,
    parameter AXI_STRM_ID = 0,
    parameter DATABEAT_SIZE = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    metaIntf.m sq_rd,    // #(.STYPE(req_t))
    metaIntf.s cq_rd,    // #(.STYPE(ack_t))
    AXI4S.s rdma_in,     // #(AXI_DATA_BITS)
                         // NOTE: This must be axis_rreq_recv[AXI_STRM_ID]

    ready_valid_i.s in,  // #(rdma_buffer_t)

    ndata_i.m out        // #(data8_t, DATABEAT_SIZE)
);

typedef enum logic {
    ST_IDLE,
    ST_READING
} state_t;

// ------- State machine state -----------------------------------------------
state_t state;
logic keep_ack;
logic keep_last;

// ------- Combinatorial state -----------------------------------------------
logic ack;
logic last;

task reset();
    state <= ST_IDLE;
    keep_ack <= 0;
    keep_last <= 0;
endtask

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        reset();
    end else begin
        if (cq_rd.ready && cq_rd.valid) begin
          keep_ack <= 1;
        end

        if (out.ready && out.valid && out.last) begin
          keep_last <= 1;
        end

        case (state)
            ST_IDLE: begin
                if (sq_rd.ready && sq_rd.valid) begin
                    state <= ST_READING;
                end
            end

            ST_READING: begin
                if (ack && last) begin
                    reset();
                end
            end
        endcase
    end
end

assign ack = (cq_rd.ready && cq_rd.valid) ? 1 : keep_ack;
assign last = (out.ready && out.valid && out.last) ? 1 : keep_last;

AXIToNData #(
  .data_t(data8_t),
  .NUM_ELEMENTS(DATABEAT_SIZE)
) inst_axi_to_ndata(
    .clk(clk),
    .rst_n(rst_n),

    .in(rdma_in),
    .out(out)
);

rdma_buffer_t buffer;
assign buffer = in.data;

assign sq_rd.data = '{
    last: 1'b1,
    dest: AXI_STRM_ID,
    len: buffer.size,
    vaddr: buffer.vaddr,
    strm: STRM_RDMA,
    opcode: LOCAL_READ,
    default: '0
};
assign sq_rd.valid = (state == ST_IDLE) && in.valid && in.ready;

// Accept acks when we haven't received one for the current transaction
assign cq_rd.ready = ~keep_ack;
// We can take in another input buffer to read when we're not reading
assign in.ready = (state == ST_IDLE) && sq_rd.ready;

endmodule
