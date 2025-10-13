`timescale 1ns / 1ps

import lynxTypes::*;

module runlength_decoder #(
    parameter integer OUT_BYTE_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    // These are only considered for the first transmission of the below 'in' AXI stream.
    input logic [5:0] start, // Start of the data in the chunk
    input logic [3:0] bit_width,
    input logic [30:0] run_length,

    // 'in.keep' and 'in.last' signals are ignored,
    // the respective information is inferred from start, bit_width and run_length.
    AXI4SC.s in,
    AXI4SC.m out
);
    localparam OUT_BIT_WIDTH = OUT_BYTE_WIDTH * 8;
    localparam OUT_VALUES = AXI_DATA_BITS / OUT_BIT_WIDTH;


    
    logic [1:0] state;
    logic [63:0] value;
    // Remaining number of values in the run
    logic [30:0] count;



    // Only need to handshake if the value uses two bytes and is split between two chunks.
    // Otherwise, handshake is deferred to the time when the chunk is processed completely.
    assign in.tready = state == 2'd0 && in.tvalid && start*8 + bit_width > AXI_DATA_BITS;

    // State machine
    always_ff @(posedge clk) begin
        if (rst_n) begin
            case (state)
                2'd0: begin
                    if (in.tvalid) begin
                        // Read first part of value
                        value[7:0] <= in.tdata[start*8+:8];
                        count <= run_length;

                        if (in.tready) begin
                            // Value is split
                            state <= 2'd1;
                        end else begin
                            if (bit_width > 8) begin
                                value[15:8] <= in.tdata[(start+1)*8+:8];
                            end
                            state <= 2'd2;
                        end
                    end
                end
                2'd1: begin
                    if (in.tvalid) begin
                        // Read second byte of value
                        value[15:8] <= in.tdata[7:0];
                        state <= 2'd2;
                    end
                end
                2'd2: begin
                    // Generate output
                    if (out.tready && out.tvalid) begin
                        count <= count - OUT_VALUES;

                        if (out.tlast) begin
                            // Internal reset
                            state <= 2'd0;
                            value <= 64'd0;
                            count <= 30'd0;
                        end
                    end
                end
            endcase
        end else begin
            state <= 2'd0;
            value <= 64'd0;
            count <= 30'd0;
        end
    end

    // Output AXI stream
    always_comb begin
        out.tdata = {(OUT_VALUES){value[OUT_BIT_WIDTH-1:0]}};
        out.tlast = count <= OUT_VALUES;
        out.tvalid = state == 2'd2 && count > 30'd0;
        
        for (int i = 0; i < OUT_VALUES; i++) begin
            out.tkeep[i*OUT_BYTE_WIDTH+:OUT_BYTE_WIDTH] = {(OUT_BYTE_WIDTH){i < count ? 1'b1 : 1'b0}};
        end
    end



// `ifdef DEBUG
//     // ILA debug
//     ila_rle_decoder ila_debug (
//         .clk(clk),

//         .probe0(rst_n),
//         .probe1(start),
//         .probe2(bit_width),
//         .probe3(run_length),

//         .probe4(state),
//         .probe5(value),
//         .probe6(count),

//         .probe7(in.tdata),
//         .probe8(in.tkeep),
//         .probe9(in.tlast),
//         .probe10(in.tvalid),
//         .probe11(in.tready),
//         .probe12(out.tdata),
//         .probe13(out.tkeep),
//         .probe14(out.tlast),
//         .probe15(out.tvalid),
//         .probe16(out.tready)
//     );
// `endif
endmodule