`timescale 1ns / 1ps

import lynxTypes::*;

module bitpacking_decoder #(
    parameter integer OUT_BYTE_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    // These are only considered for the first transmission of the below 'in' AXI stream
    input logic [5:0] start, // Start of the data in the chunk
    input logic [3:0] bit_width,
    input logic [30:0] run_length,

    // 'in.keep' and 'in.last' signals are ignored,
    // the respective information is inferred from start, bit_width and run_length
    AXI4SC.s in,
    AXI4SC.m out
);
    localparam OUT_BIT_WIDTH = OUT_BYTE_WIDTH * 8;
    localparam OUT_VALUES = AXI_DATA_BITS / OUT_BIT_WIDTH;



    logic [3:0] in_bit_width;
    // Remaining number of values in the run
    logic [30:0] count; 
    // Buffer for input data
    // (extra space is needed to prevent overflow when reading new data while there is still some to be unpacked)
    logic [AXI_DATA_BITS*2-1:0] in_data;
    // Was the data currently on the input stream already read?
    logic data_read;
    // Count of valid bytes in 'in_data' starting from LSB
    logic [6:0] in_data_bytes;
    // How many bytes are needed to fill the next chunk?
    logic [6:0] bytes_needed;



    /*
        We handshake on the input AXI stream only when we processed the entire chunk already.
        This is because the BPE run might end somewhere in the middle and the next header will
        have to be read right after, so to simplify the reading of the headers we leave the current
        data in the stream until we can be sure it is not needed anymore.
    */

    assign in.tready = rst_n && data_read && in_data_bytes < bytes_needed;

    always_ff @(posedge clk) begin
        // $monitor("in_data: %x", in_data);
        if (rst_n) begin
            // The below three if-conditions are mutually exclusive by definition.
            // We put them in else clauses just to be explicit.
            if (in.tvalid && in.tready) begin
                // Done with chunk
                data_read <= 1'b0;
            end else if (in.tvalid && !data_read) begin
                // New data
                if (count == 31'd0) begin
                    // First transmission
                    in_bit_width <= bit_width;
                    count <= run_length;

                    in_data[AXI_DATA_BITS-1:0] <= in.tdata >> start*8;
                    in_data_bytes <= AXI_DATA_BITS/8 - start;
                end else begin
                    in_data[in_data_bytes*8+:AXI_DATA_BITS] <= in.tdata;
                    in_data_bytes <= in_data_bytes + AXI_DATA_BITS/8;                    
                end
                data_read <= 1'b1;
            end else if (out.tvalid && out.tready) begin
                if (out.tlast) begin
                    // Internal reset
                    data_read <= 1'b0;
                    count <= 31'd0;
                    in_data_bytes <= 7'd0;
                end else begin
                    // Advance through data
                    in_data <= in_data >> OUT_VALUES*in_bit_width;
                    count <= count - OUT_VALUES;
                    in_data_bytes <= in_data_bytes - OUT_VALUES*in_bit_width/8;
                end
            end
        end else begin
            data_read <= 1'b0;
            count <= 31'd0;
            in_data_bytes <= 7'd0;
        end
    end

    // 'run_length', 'OUT_VALUES' and (by consequence) 'count' are always divisible by 8,
    // so there are no rounding issues on the division.
    assign bytes_needed = (count < OUT_VALUES ? count : OUT_VALUES) * in_bit_width / 8;

    // out
    always_comb begin
        out.tlast = count <= OUT_VALUES;

        out.tdata = 0;
        out.tkeep = 0;
        for (int i = 0; i < OUT_VALUES; i++) begin
            for (int j = 0; j < in_bit_width; j++) begin
                out.tdata[i*OUT_BIT_WIDTH+j] = in_data[i*in_bit_width+j];
            end

            out.tkeep[i*OUT_BYTE_WIDTH+:OUT_BYTE_WIDTH] = {(OUT_BYTE_WIDTH){i < count ? 1'b1 : 1'b0}};
        end

        out.tvalid = rst_n && count > 31'd0 && in_data_bytes >= bytes_needed;
    end
endmodule
