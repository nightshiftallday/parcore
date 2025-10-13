`timescale 1ns / 1ps

module config_ring_buffer #(
    parameter CONFIG_WIDTH = 16,
    parameter DEPTH = 8
) (
    input  logic clk,
    input  logic rst,

    // Control input from shared slave
    input  logic cfg_valid,
    input  logic [CONFIG_WIDTH-1:0] cfg_data,
    output logic cfg_ready,  // to master

    // Request to consume config
    input  logic read_config,
    output logic [CONFIG_WIDTH-1:0] current_config,
    output logic config_valid,
    output logic [CONFIG_WIDTH-1:0] next_config,
    output logic next_config_valid,

    output logic [$clog2(DEPTH)-1:0] debug_wr_ptr,
    output logic [$clog2(DEPTH)-1:0] debug_rd_ptr
);

    logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;
    logic [CONFIG_WIDTH-1:0] buffer[DEPTH-1:0];
    logic full, empty;

    assign full  = ((wr_ptr + 1) % DEPTH) == rd_ptr;
    assign empty = wr_ptr == rd_ptr;

    assign cfg_ready     = !full && !rst;
    assign config_valid  = !empty;
    assign next_config_valid  = ((wr_ptr - rd_ptr + DEPTH) % DEPTH) > 1;

    assign current_config = buffer[rd_ptr];
    assign next_config = buffer[(rd_ptr + 1) % DEPTH];

    assign debug_wr_ptr = wr_ptr;
    assign debug_rd_ptr = rd_ptr;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            buffer <= '{default: '0};
        end else begin
            // Handle write and read operations with proper priority
            // Both operations can happen simultaneously in a FIFO
            case ({cfg_valid && cfg_ready, read_config && config_valid})
                2'b00: begin
                    // No operation
                end
                2'b01: begin
                    // Read only
                    rd_ptr <= (rd_ptr + 1) % DEPTH;
                end
                2'b10: begin
                    // Write only
                    buffer[wr_ptr] <= cfg_data;
                    wr_ptr <= (wr_ptr + 1) % DEPTH;
                end
                2'b11: begin
                    // Simultaneous write and read - this is valid for FIFOs
                    buffer[wr_ptr] <= cfg_data;
                    wr_ptr <= (wr_ptr + 1) % DEPTH;
                    rd_ptr <= (rd_ptr + 1) % DEPTH;
                end
            endcase
        end
    end
endmodule
