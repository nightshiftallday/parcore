`timescale 1ns / 1ps

`include "libstf_macros.svh"

import lynxTypes::*;
import libstf::data8_t;

import parcore::compression_t;
import parcore::COMPRESSION_SNAPPY;
import parcore::COMPRESSION_RAW;

module Decompressor #(
    parameter NUM_BYTES = AXI_DATA_BITS / 8
) (
    input logic clk,
    input logic rst_n,

    page_decoder_config_i.s in_conf,
    ndata_i.s in,                     // #(data8_t, NUM_BYTES)

    page_decoder_config_i.m out_conf,
    ndata_i.m out                     // #(data8_t, NUM_BYTES)
);

localparam int MAX_IN_TRANSIT = 8;

`RESET_RESYNC // Reset pipelining

page_decoder_config_i conf (.clk(clk), .rst_n(reset_synced));

typedef struct {
    compression_t compression;
    page_type_t   page_type;
    data32_t      num_values;
    type_t        typ;
} config_t;

FIFO #(
    .DEPTH(2),
    .WIDTH($bits(config_t))
) inst_mask_fifo (
    .i_clk(clk),
    .i_rst_n(reset_synced),

    .i_data({in_conf.compression, in_conf.page_type, in_conf.num_values, in_conf.typ}),
    .i_valid(in_conf.valid),
    .i_ready(in_conf.ready),

    .o_data({conf.compression, conf.page_type, conf.num_values, conf.typ}),
    .o_valid(conf.valid),
    .o_ready(conf.ready),

    .o_filling_level()
);

typedef enum logic {
    ST_FORWARD,
    ST_DONE
} state_t;
state_t state;

assign out_conf.compression = conf.compression;
assign out_conf.page_type = conf.page_type;
assign out_conf.num_values = conf.num_values;
assign out_conf.typ = conf.typ;
assign out_conf.valid = state == ST_FORWARD && conf.valid;

always_ff @(posedge clk) begin
    if (reset_synced == 1'b0) begin
        state <= ST_FORWARD;
    end else begin
        case (state)
            ST_FORWARD: begin
                if (conf.valid && out_conf.ready) begin
                    state <= ST_DONE;
                end
            end

            ST_DONE: begin
                if (conf.valid && conf.ready) begin
                    state <= ST_FORWARD;
                end
            end
        endcase
    end
end

ndata_i #(data8_t, NUM_BYTES) ins[1:0] ();
ndata_i #(data8_t, NUM_BYTES) outs[1:0] ();

// ------ Bypass wiring -------------

NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_bypass (
    .clk(clk),
    .rst_n(reset_synced),

    .in(ins[1]),
    .out(outs[1])
);

// ------ Decompressor wiring -------------

ndata_i #(data8_t, NUM_BYTES) decompressor_inner ();
VHSNUnzipWrapper #(NUM_BYTES) inst_vhsnunzip_wrapper (
    .clk(clk),
    .rst_n(reset_synced),

    .in(ins[0]),
    .out(decompressor_inner)
);
NDataSkidBuffer #(data8_t, NUM_BYTES) inst_skid_buffer_vhsnunzip (
    .clk(clk),
    .rst_n(reset_synced),

    .in(decompressor_inner),
    .out(outs[0])
);

// ------ (De)Multiplexing -------------

ready_valid_i #(compression_t) compression_meta ();

// These ready and valid assignments are to make sure that the metadata is
// forwarded before we move to the next state.
assign conf.ready = compression_meta.ready && state == ST_DONE;
assign compression_meta.valid = conf.valid && state == ST_DONE;
assign compression_meta.data = conf.compression;

ready_valid_i #(compression_t) metas[1:0] ();

ReadyValidDuplicator #(2) inst_meta_duplicator (
    .clk(clk),
    .rst_n(reset_synced),

    .in(compression_meta),
    .out(metas)
);

DataDemultiplexer #(2) inst_demultiplexer (
    .clk(clk),
    .rst_n(reset_synced),

    .select(metas[0]),

    .in(in),
    .out(ins)
);

DataMultiplexer #(data8_t, NUM_BYTES, 2) inst_multiplexer (
    .clk(clk),
    .rst_n(reset_synced),

    .select(metas[1]),

    .in(outs),
    .out(out)
);

endmodule
