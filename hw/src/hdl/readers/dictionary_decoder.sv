`timescale 1ns / 1ps

import lynxTypes::*;

module dictionary_decoder #(
    parameter integer OUT_BYTE_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    input logic mode, // Read <> 0; Write <> 1

    AXI4SC.s in,
    AXI4SC.m out
);
    localparam OUT_BIT_WIDTH = OUT_BYTE_WIDTH * 8;
    localparam OUT_VALUES = AXI_DATA_BITS / OUT_BIT_WIDTH;
    localparam ADDR_BITS = 11; // More address bits unlock high input bit widths but use more dictionary RAM
    localparam INDEX_BITS = $clog2(OUT_VALUES);
    localparam DICT_CNT = OUT_VALUES / 2; // (dual-port)
    localparam FIFO_DATA_BITS = AXI_DATA_BITS + AXI_DATA_BITS/8 + 1; // (tdata + tkeep + tlast)

    

    // RAM ports
    logic dict_a_en;
    logic [OUT_BYTE_WIDTH-1:0] dict_a_we;
    logic [ADDR_BITS-1:0] dict_a_addr [DICT_CNT-1:0];
    logic dict_b_en;
    logic [ADDR_BITS-1:0] dict_b_addr [DICT_CNT-1:0];
    logic [OUT_BIT_WIDTH-1:0] dict_a_data_in;
    logic [OUT_BIT_WIDTH-1:0] dict_a_data_out [DICT_CNT-1:0];
    logic [OUT_BIT_WIDTH-1:0] dict_b_data_out [DICT_CNT-1:0];

    // Input AXI buffers
    logic [AXI_DATA_BITS-1:0] in_data;
    logic in_last;
    logic in_ready;

    // Index for dictionary writing
    logic [ADDR_BITS-1:0] input_index;
    // Is dictionary content being written to RAM?
    logic write_dict;

    // FIFO ports
    logic fifo_rd;
    logic fifo_wr;
    logic fifo_ready_rd;
    logic fifo_ready_wr;
    logic [FIFO_DATA_BITS-1:0] fifo_data_in;
    logic [FIFO_DATA_BITS-1:0] fifo_data_out;



    // in.tready
    always_comb begin
        if (rst_n) begin
            in.tready = write_dict ? in_ready : fifo_ready_wr;
        end else begin
            in.tready = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (mode || write_dict) begin
                // Write dictionary
                if (in.tready) begin
                    if (in.tvalid) begin
                        // Read input data
                        in_data <= in.tdata;
                        in_last <= in.tlast;

                        // Keep writing until end of stream regardless of 'mode'
                        write_dict <= 1'b1; 
                        in_ready <= 1'b0;
                    end
                end else begin
                    input_index <= input_index + 1;

                    if (input_index[INDEX_BITS-1:0] == {(INDEX_BITS){1'b1}}) begin
                        in_ready <= 1'b1;

                        if (in_last) begin
                            // Reset to reading mode
                            input_index <= 0;
                            write_dict <= 1'b0;
                        end
                    end
                end
            end else begin
                // Read dictionary           
                if (in.tready && in.tvalid) begin
                    fifo_data_in[FIFO_DATA_BITS-2:AXI_DATA_BITS] <= in.tkeep;
                    fifo_data_in[FIFO_DATA_BITS-1] <= in.tlast;

                    fifo_wr <= 1'b1;
                end else begin
                    fifo_wr <= 1'b0;
                end
            end
        end else begin
            // Reset to writing mode
            write_dict <= 1'b1;
            in_ready <= 1'b1;
            input_index <= 0;
        end
    end

    // 'tdata' part of 'fifo_data_in'
    generate
        for (genvar i = 0; i < DICT_CNT; i++) begin
            always_comb begin
                fifo_data_in[i*2*OUT_BIT_WIDTH+:OUT_BIT_WIDTH] = dict_a_data_out[i];
                fifo_data_in[(i*2+1)*OUT_BIT_WIDTH+:OUT_BIT_WIDTH] = dict_b_data_out[i];
            end
        end     
    endgenerate

    assign out.tdata = fifo_data_out[AXI_DATA_BITS-1:0];
    assign out.tkeep = fifo_data_out[FIFO_DATA_BITS-2:AXI_DATA_BITS];
    assign out.tlast = fifo_data_out[FIFO_DATA_BITS-1];
    assign out.tvalid = fifo_ready_rd;
    assign fifo_rd = out.tready && out.tvalid;

    assign dict_a_en = 1'b1;
    assign dict_a_we = {(OUT_BYTE_WIDTH){write_dict ? 1'b1 : 1'b0}};
    assign dict_b_en = 1'b1;
    assign dict_a_data_in = in_data[input_index[INDEX_BITS-1:0]*OUT_BIT_WIDTH+:OUT_BIT_WIDTH];

    // dict_a_addr[] and dict_b_addr[]
    generate
        for (genvar i = 0; i < DICT_CNT; i++) begin
            always_comb begin
                dict_a_addr[i] = write_dict ? input_index : in.tdata[i*2*OUT_BIT_WIDTH+:ADDR_BITS];
                dict_b_addr[i] = in.tdata[(i*2+1)*OUT_BIT_WIDTH+:ADDR_BITS];
            end
        end
    endgenerate



    // RAM instantiation
    generate
        for (genvar i = 0; i < DICT_CNT; i++) begin : dict_gen
            ram_tp_nc #(
                .ADDR_BITS(ADDR_BITS),
                .DATA_BITS(OUT_BIT_WIDTH)
            ) dictionary (
                .clk(clk),

                .a_en(dict_a_en),
                .a_we(dict_a_we),
                .a_addr(dict_a_addr[i]),
                .b_en(dict_b_en),
                .b_addr(dict_b_addr[i]),
                .a_data_in(dict_a_data_in),
                .a_data_out(dict_a_data_out[i]),
                .b_data_out(dict_b_data_out[i])
            );
        end
    endgenerate

    // Output FIFO
    lookahead_fifo #(
        .DATA_BITS(FIFO_DATA_BITS),
        .FIFO_SIZE(2) // FIFO is only really needed to deal with clocked RAM, so keep shallow in favor of utilization
    ) output_fifo (
        .aclk(clk),
        .aresetn(rst_n),

	    .rd(fifo_rd),
	    .wr(fifo_wr),

	    .ready_rd(fifo_ready_rd),
	    .ready_wr(fifo_ready_wr),

	    .data_in(fifo_data_in),
	    .data_out(fifo_data_out)
    );
endmodule
