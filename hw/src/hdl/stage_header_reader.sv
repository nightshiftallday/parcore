`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;
import reader_pkg::*;

// function automatic integer KEEP_TO_BYTES(input logic [AXI_DATA_BITS/8-1:0] tkeep);
//     integer i;
//     begin
//         KEEP_TO_BYTES = 0;
//         for (i = 0; i < AXI_DATA_BITS/8; i = i + 1) begin
//             if (tkeep[i])
//                 KEEP_TO_BYTES = KEEP_TO_BYTES + 1;
//         end
//     end
// endfunction


module page_header_reader #(
    parameter ADDITIONAL_RESET_CYCLES = 0,
    parameter BYTES = AXI_DATA_BITS / 8,
    parameter OFFSET_WIDTH = $clog2(BYTES)

)(
    input logic clk,
    input logic rst_n,

    // Config interface (connects to control slave)
    input  logic cfg_valid,
    input  logic [CONFIG_WIDTH-1:0] cfg_data,
    output logic cfg_ready,

    output  logic header_data_valid,
    output  logic [HEADER_DATA_WIDTH-1:0] header_data,
    input logic header_data_ready,

    // Data Interfaces
    AXI4SR.s  in_stream,
    AXI4SR.m out_stream
);
    AXI4SC in_stream_ff(clk);
    AXI4SC in_stream_config(clk);
    assign in_stream_config.tdata = in_stream.tdata;
    assign in_stream_config.tkeep = in_stream.tkeep;
    assign in_stream_config.tlast = in_stream.tlast;
    assign in_stream_config.tvalid = in_stream.tvalid;
    assign in_stream_config.tconfig = '0;
    assign in_stream.tready = in_stream_config.tready;

    OverflowRegister input_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in(in_stream_config),
        .out(in_stream_ff)
    );


    logic inside_pkt_ff;  // 1 after first beat until TLAST (accepted)
    // Convenience
    wire beat_accepted = in_stream_ff.tvalid && in_stream_ff.tready;

    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        inside_pkt_ff <= 1'b0;
    end else if (beat_accepted) begin
        if (!inside_pkt_ff) begin
        // First accepted beat (SOP): be inside the packet only if not last
        inside_pkt_ff <= ~in_stream_ff.tlast;
        end else begin
        // Inside packet: drop to 0 when the last beat is accepted
        if (in_stream_ff.tlast) inside_pkt_ff <= 1'b0;
        end
    end
    end

    wire first_beat_comb = beat_accepted && !inside_pkt_ff;

    reg parser_res_buffer_valid; //Belongs to parsing handshake. Up here because of warning.
    logic [AXI_DATA_BITS-1:0] first_packet_data;
    logic [HEADER_DATA_WIDTH-1:0] header_data_comb;


    assign first_packet_data = (first_beat_comb) ? in_stream_ff.tdata : '0 ;
    logic [7:0] field_type_0_comb, field_type_1_comb, field_type_2_comb, field_type_3_comb, field_type_4_comb, field_type_5_comb, field_type_6_comb;
    logic [31:0] ptype_comb, uncomp_size_comb, comp_size_comb, crc_comb, num_vals_comb, encoding_comb;
    logic [3:0] length_0_comb, length_1_comb, length_2_comb, length_3_comb, length_4_comb, length_5_comb;
    logic crc_present, parse_valid;

    assign header_data_comb = (!first_beat_comb) ? '0 : {ptype_comb[1:0], encoding_comb[3:0], num_vals_comb};

    assign header_data = (!inside_pkt_ff) ? header_data_comb : '0;
    assign header_data_valid = first_beat_comb;

    // always_ff @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         parser_res_buffer_valid       <= 1'b0;
    //     end else begin
    //         if (header_data_valid && header_data_ready) begin
    //         parser_res_buffer_valid <= 1'b0;
    //         end

    //         if (first_beat_comb && !header_data_ready) begin
    //             header_data_buffer <= header_data_comb;
    //             parser_res_buffer_valid       <= 1'b1;
    //         end
    //     end
    // end

    varint3_extractor_with_field_types #() header_parser (
        .data_bus(first_packet_data),
        .field_type_0(field_type_0_comb),
        .length_0(length_0_comb),
        .value_0(ptype_comb),
        .field_type_1(field_type_1_comb),
        .length_1(length_1_comb),
        .value_1(uncomp_size_comb),
        .field_type_2(field_type_2_comb),
        .length_2(length_2_comb),
        .value_2(comp_size_comb),
        .field_type_3(field_type_3_comb),
        .length_3(length_3_comb),
        .value_3(crc_comb),
        .field_type_4(field_type_4_comb),
        .field_type_5(field_type_5_comb),
        .length_4(length_4_comb),
        .value_4(num_vals_comb),
        .field_type_6(field_type_6_comb),
        .length_5(length_5_comb),
        .value_5(encoding_comb),
        .field_set_3(crc_present),
        .parse_valid(parse_valid)
    );

    AXI4SC in_stream_stalled(clk);
    assign in_stream_stalled.tdata = in_stream_ff.tdata;
    assign in_stream_stalled.tkeep = in_stream_ff.tkeep;
    assign in_stream_stalled.tlast = in_stream_ff.tlast;
    assign in_stream_stalled.tvalid = (header_data_ready) ? in_stream_ff.tvalid : 1'b0;
    assign in_stream_ff.tready = in_stream_stalled.tready;

    AXI4SC in_stream_extracted(clk);

    OverflowRegister shifter_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in(in_stream_stalled),
        .out(in_stream_extracted)
    );

    // assign out_stream.tdata = in_stream_extracted.tdata;
    // assign out_stream.tkeep = in_stream_extracted.tkeep;
    // assign out_stream.tlast = in_stream_extracted.tlast;
    // assign out_stream.tvalid = in_stream_extracted.tvalid;
    // assign in_stream_extracted.tready = out_stream.tready;


    typedef enum logic [2:0] {
        WAITING_FOR_INPUT_DONE,
        WAITING_FOR_OUTPUT_DONE,
        WAITING_FOR_CONFIG,
        WARMUP
    } state_t;

    state_t state, next_state;
    reg [3:0] pages_done_counter; // cycles in reset state

    logic startup_done;
    logic read_config;
    logic config_valid;
    logic [CONFIG_WIDTH-1:0] current_config;
    logic next_config_valid;
    logic [CONFIG_WIDTH-1:0] next_config;

    logic input_done_comb, output_done_comb;
    assign input_done_comb  = in_stream_extracted.tvalid && in_stream_extracted.tready && in_stream_extracted.tlast;
    assign output_done_comb = out_stream.tvalid && out_stream.tready && out_stream.tlast;

    // State Machine
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= WAITING_FOR_CONFIG;
        end else begin
            state <= next_state;
         end
    end
    always_ff @(posedge clk) begin
    if (!rst_n) begin
        startup_done <= 0;
    end else if (config_valid)
        startup_done <= 1;
    end

    reg [15:0] header_bytes_left;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            header_bytes_left <= 0;
            pages_done_counter <= 0;
        end else if (state == WARMUP) begin
            header_bytes_left <= current_config[HEADER_SIZE_START+15:HEADER_SIZE_START];
        end else if (read_config) begin
            pages_done_counter <= pages_done_counter + 1;
            header_bytes_left <= next_config[HEADER_SIZE_START+15:HEADER_SIZE_START];
        end else if (in_stream_extracted.tvalid && in_stream_extracted.tready) begin
            if (header_bytes_left >= $countones(in_stream_extracted.tkeep)) begin
                header_bytes_left <= header_bytes_left - $countones(in_stream_extracted.tkeep);
            end else begin
                header_bytes_left <= 0;
            end
        end
    end


    always_comb begin
        next_state = state;
        read_config = 1'b0;

        case (state)
            // First AXI transfer of new stream
            WAITING_FOR_INPUT_DONE: begin
                if (input_done_comb && output_done_comb) begin
                    if (next_config_valid) begin
                        read_config = 1'b1;
                        next_state = WAITING_FOR_INPUT_DONE;
                    end else begin
                        next_state = WAITING_FOR_CONFIG;
                    end
                end else if (input_done_comb) begin
                    // First input was also last
                    next_state = WAITING_FOR_OUTPUT_DONE;
                end
            end

            // Wait until the output interface finishes
            WAITING_FOR_OUTPUT_DONE: begin
                if (output_done_comb) begin
                    if (next_config_valid) begin
                        read_config = 1'b1;
                        next_state = WAITING_FOR_INPUT_DONE;
                    end else begin
                        next_state = WAITING_FOR_CONFIG;
                    end
                end
            end

            // Config comes from outside, one-time or streamed, plus waiting for header output
            WAITING_FOR_CONFIG: begin
                if (config_valid && next_config_valid) begin
                    read_config = 1'b1;
                    next_state = WAITING_FOR_INPUT_DONE;
                end else if (config_valid && !startup_done) begin
                    next_state = WARMUP;
                end
            end
            WARMUP: begin
                next_state = WAITING_FOR_INPUT_DONE;
            end

        endcase
    end




    AXI4SC shifter_in(clk);
    AXI4SC shifter_out(clk);
    logic ready_for_input;
    assign ready_for_input = (state == WAITING_FOR_INPUT_DONE);
    // logic bypass_active;
    // assign bypass_active = (current_config[HEADER_SIZE_START+15:HEADER_SIZE_START] == 0);


    assign shifter_in.tdata = in_stream_extracted.tdata;
    assign shifter_in.tkeep = (header_bytes_left < AXI_DATA_BITS/8) ? (in_stream_extracted.tkeep & ~((1 << header_bytes_left) - 1)) : '0;
    assign shifter_in.tlast = in_stream_extracted.tlast;
    assign shifter_in.tvalid = (ready_for_input) ? in_stream_extracted.tvalid : 1'b0;
    assign in_stream_extracted.tready = (ready_for_input) ? shifter_in.tready : 1'b0;
    // Snappy decompressor
    StreamNormalizer #(.WIDTH(AXI_DATA_BITS), .ENABLE_COMPACTOR(0), .CELL_WIDTH(8)) header_shifter (
        .aclk(clk),
        .aresetn(rst_n),
        // .i_offset(header_bytes_left[OFFSET_WIDTH-1:0]),
        .i_data(shifter_in),
        .o_data(shifter_out)
    );

    always_comb begin
        out_stream.tdata = shifter_out.tdata;
        out_stream.tkeep = shifter_out.tkeep;
        out_stream.tlast = shifter_out.tlast;
        out_stream.tvalid = shifter_out.tvalid;
        shifter_out.tready = out_stream.tready;
    end



    // Config Ring Buffer
    config_ring_buffer #(
        .CONFIG_WIDTH(CONFIG_WIDTH),
        .DEPTH(BUFFER_DEPTH)
    ) config_fifo (
        .clk(clk),
        .rst(!rst_n),
        .cfg_valid(cfg_valid),
        .cfg_data(cfg_data),
        .cfg_ready(cfg_ready),
        .read_config(read_config),
        .current_config(current_config),
        .config_valid(config_valid),
        .next_config(next_config),
        .next_config_valid(next_config_valid)
    );

endmodule