`timescale 1ns / 1ps

import lynxTypes::*;

/*
    CAUTION
    When the last input chunk is empty, there might be no output chunk with tlast set.
    The output stream can be considered terminated on the last input handshake.
*/
module header_reader #(
    parameter integer OUT_BYTE_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,
    
    // Only used for the very first transmission
    input logic [5:0] start, 
    input logic [3:0] bit_width,

    AXI4SC.s in, 
    AXI4SC.m out
);
    typedef enum {
        IDLE,
        HEADER1,
        HEADER2,
        RUN,
        LAST
    } state_t;



    state_t state;
    // Current index in the input stream chunk
    logic [6:0] in_data_index;
    logic [3:0] in_bit_width;
    // Header of the current run
    logic [39:0] header;
    // Length of the header (flip-flop)
    logic [2:0] header_length_ff;
    // Length of the header (combinatorial)
    logic [2:0] header_length_comb;
    // Does the header overflow the current chunk?
    logic header_overflow;
    // Was the header read completely? (flip-flop)
    logic header_done_ff;
    // Was the header read completely? (combinatorial)
    logic header_done_comb;

    logic active;
    logic mode;
    // Number of values in the current run
    logic [34:0] run_length;
    // Encoded size of the current run
    logic [32:0] encoded_size;
    // Starting index of the next run in the input chunk
    logic [5:0] next_index;
    // Is the current run the last one?
    logic last_run;
    // Handshake helper for the last input chunk
    logic last_ready;

    AXI4SC dec_in(clk);
    AXI4SC dec_out(clk);

    // Overflow buffer for AXI stream normalization
    logic [AXI_DATA_BITS-1:0] out_overflow;
    // Number of valid bytes in 'out_overflow'
    logic [5:0] out_overflow_count;
    // Number of valid bytes from both decoder output and overflow buffer
    logic [6:0] total_count;

    logic [$clog2(64):0] in_cnt;
    assign in_cnt = $countones(dec_out.tkeep);


    // State machine
    always_ff @(posedge clk) begin
        if (rst_n) begin
            case (state)
                IDLE: begin
                    if (in.tvalid) begin
                        // First transmission
                        in_data_index[5:0] <= start;
                        in_data_index[6] <= 1'b0;
                        in_bit_width <= bit_width;

                        state <= HEADER1;
                    end
                end
                HEADER1: begin
                    // Read first part of header
                    header <= in.tdata[in_data_index*8+:40];
                    header_length_ff <= header_length_comb;
                    header_done_ff <= header_done_comb;

                    if (header_overflow) begin
                        in_data_index <= 7'd0;

                        state <= HEADER2;
                    end else begin
                        in_data_index <= in_data_index + header_length_comb;

                        state <= RUN;
                    end
                end
                HEADER2: begin
                    // New chunk
                    if (in.tvalid) begin
                        // Read remainder of header
                        header[header_length_ff*8+:40] <= in.tdata[39:0];
                        header_done_ff <= 1'b1;
                        if (!header_done_ff) begin
                            header_length_ff <= header_length_ff + header_length_comb;

                            in_data_index <= header_length_comb;
                        end

                        if (in.tkeep[0]) begin
                            state <= RUN;
                        end else begin
                            // Last, empty chunk
                            last_ready <= 1'b1;

                            state <= LAST;
                        end
                    end
                end
                RUN: begin
                    if (dec_out.tready && dec_out.tvalid && dec_out.tlast) begin
                        // If the current run ends exactly with the current chunk, signify that a handshake
                        // should be performed with bit 6 of 'in_data_index', otherwise advance normally
                        in_data_index <= next_index == 6'd0 ? 7'h40 : next_index;

                        if (last_run) begin
                            last_ready <= 1'b1;

                            state <= LAST;
                        end else begin
                            state <= HEADER1;
                        end
                    end
                end
                LAST: begin
                    if (in.tready && in.tvalid) begin
                        // Last, leftover handshake
                        last_ready <= 1'b0;
                    end

                    if (!out.tvalid || out.tready) begin
                        // Internal reset after residual overflow was transmitted
                        state <= IDLE;
                    end
                end
                default: ;
            endcase
        end else begin
            in_data_index <= 7'd0;
            in_bit_width <= 4'd0;
            header <= 40'd0;
            header_length_ff <= 3'd0;
            last_ready <= 1'b0;

            state <= IDLE;
        end
    end

    // header_length_comb, header_overflow and header_done_comb
    always_comb begin
        header_length_comb = AXI_DATA_BITS/8 - in_data_index;
        header_overflow = 1'b1;
        header_done_comb = 1'b0;
        for (int i = 0, done = 0; i < AXI_DATA_BITS/8; i++) begin
            if (!done && i >= in_data_index && !in.tdata[i*8+7]) begin
                header_length_comb = i - in_data_index + 1;
                header_overflow = i == AXI_DATA_BITS/8 - 1 ? 1'b1 : 1'b0;
                header_done_comb = 1'b1;

                done = 1;
            end
        end
    end

    // run_length
    always_comb begin
        run_length = 34'd0;
        for (int i = 0; i < 5; i++) begin
            if (i < header_length_ff) begin
                run_length[i*7+:7] = header[i*8+:7];
            end
        end
        run_length >>= 1;
        if (mode) begin
            run_length *= 8;
        end
    end

    assign active = state == RUN;
    assign mode = header[0];
    assign encoded_size = mode ? run_length*in_bit_width/8 : (in_bit_width + 7)/8;
    assign next_index = in_data_index + encoded_size;
    assign last_run = (next_index == 6'd0 && in.tlast) || !in.tkeep[next_index];

    // Input AXI stream
    always_comb begin
        dec_in.tdata = in.tdata;
        dec_in.tkeep = in.tkeep;
        dec_in.tlast = in.tlast;

        case (state)
            HEADER1: begin 
                in.tready = header_overflow;
                dec_in.tvalid = 1'b0;
            end // Get next chunk if header is split
            RUN: begin
                in.tready = dec_in.tready;
                dec_in.tvalid = in.tvalid;
            end
            LAST: begin 
                in.tready = last_ready;
                dec_in.tvalid = in.tvalid;
            end
             // Handshake for the last input chunk
            default: begin 
                in.tready = 1'b0;
                dec_in.tvalid = 1'b0;
            end
        endcase
    end
 
    // out_overflow and out_overflow_count
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (dec_out.tready && dec_out.tvalid) begin
                if (total_count >= AXI_DATA_BITS/8) begin
                    // Decoder output with existing overflow is exactly one chunk or overflows,
                    // so read overflow and set 'out_overflow_count'
                    out_overflow <= dec_out.tdata[((in_cnt == 0 ? AXI_DATA_BITS / 8 : in_cnt) - total_count[5:0]) * 8+:AXI_DATA_BITS];
                    out_overflow_count <= total_count[5:0];
                end else begin
                    // Decoder output with existing overflow cannot fill an entire chunk,
                    // so just append output to overflow
                    out_overflow[out_overflow_count*8+:AXI_DATA_BITS] <= dec_out.tdata;
                    if (dec_out.tlast && last_run) begin
                        // It is the last chunk and being transmitted regularly
                        out_overflow_count <= 6'd0;
                    end else begin
                        out_overflow_count <= total_count[5:0];
                    end
                end
            end
        end else begin
            out_overflow <= 0;
            out_overflow_count <= 6'd0;
        end
    end

    // total_count
    always_comb begin
        total_count = 7'h40;
        for (int i = 0, done = 0; i < AXI_DATA_BITS/8; i++) begin
            if (!done && !dec_out.tkeep[i]) begin
                total_count = i;

                done = 1;
            end
        end

        total_count += out_overflow_count;
    end

    // out and dec_out.tready
    always_comb begin
        out.tdata = out_overflow;
        out.tdata[out_overflow_count*8+:AXI_DATA_BITS] = dec_out.tdata;

        for (int i = 0; i < AXI_DATA_BITS/8; i++) begin
            out.tkeep[i] = i < (state == LAST ? out_overflow_count : total_count) ? 1'b1 : 1'b0;
        end

        out.tlast = 1'b0;
        out.tvalid = 1'b0;
        if (rst_n) begin
            if (dec_out.tvalid) begin
                if (total_count >= AXI_DATA_BITS/8) begin
                    out.tvalid = 1'b1;
                    if (total_count == AXI_DATA_BITS/8 && dec_out.tlast && last_run) begin
                        // Last chunk happens to be exactly full
                        out.tlast = 1'b1;
                    end
                end else if (dec_out.tlast && last_run) begin
                    // Last chunk with overflow is only partially valid
                    out.tlast = 1'b1;
                    out.tvalid = 1'b1;
                end
            end else if (state == LAST && out_overflow_count > 0) begin
                // Transmit residual overflow as last chunk
                out.tlast = 1'b1;
                out.tvalid = 1'b1;
            end
        end

        dec_out.tready = out.tready;
    end

    decoding_arbiter #(
        .OUT_BYTE_WIDTH(OUT_BYTE_WIDTH)
    ) decoder (
        .clk(clk),
        .rst_n(rst_n),
        
        .active(active),
        .mode(mode),

        .start(in_data_index[5:0]),
        .bit_width(in_bit_width),
        .run_length(run_length[30:0]),

        .in(dec_in),
        .out(dec_out)
    );

    // OverflowRegister output_fifo (
    //     .clk(clk),
    //     .rst_n(rst_n),

    //     .in(dec_out_ff),
    //     .out(dec_out)
    // );

endmodule

