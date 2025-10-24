`timescale 1ns / 1ps

`include "axi_macros.svh"

`include "parcore_types.svh"
import parcore::*;


module Decompressor (
    input logic clk,
    input logic rst_n,

    ready_valid_i.s in_meta, // #(page_metadata_t)
    AXI4SR.s in,

    ready_valid_i.m out_meta, // #(page_metadata_t)
    AXI4S.m out
);

ready_valid_i #(page_metadata_t) meta ();
HoldForward #(page_metadata_t) hold_meta_transaction_inst (
    .clk(clk),
    .rst_n(rst_n),

    .in_meta(in_meta),
    .out_meta(out_meta),
    // We want to pause the current metadata when we receive the last databeat
    .pause(in.tvalid && in.tready && in.tlast),
    // We want to drop the current metadata when we send the last databeat
    .drop(out.tvalid && out.tready && out.tlast),

    .meta(meta)
);

AXI4S decompressor_in(clk);
AXI4S decompressor_out(clk);
assign decompressor_in.tdata = in.tdata;
assign decompressor_in.tkeep = in.tkeep;
assign decompressor_in.tlast = in.tlast;
assign decompressor_in.tvalid = meta.ready && meta.valid && (meta.data.compression == COMPRESSION_SNAPPY && in.tvalid);

AXI4S bypass_in(clk);
AXI4S bypass_out(clk);
assign bypass_in.tdata = in.tdata;
assign bypass_in.tkeep = in.tkeep;
assign bypass_in.tlast = in.tlast;
assign bypass_in.tvalid = meta.ready && meta.valid && (meta.data.compression == COMPRESSION_RAW && in.tvalid);

reg decompressor_input_paused;
assign in.tready = meta.ready && meta.valid && (
    (meta.data.compression == COMPRESSION_SNAPPY && decompressor_in.tready && !decompressor_input_paused)
 || (meta.data.compression == COMPRESSION_RAW && bypass_in.tready)
);

assign out.tvalid = meta.valid && (meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.tvalid : bypass_out.tvalid);
assign out.tdata  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.tdata  : bypass_out.tdata;
assign out.tkeep  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.tkeep  : bypass_out.tkeep;
assign out.tlast  = meta.data.compression == COMPRESSION_SNAPPY ? decompressor_out.tlast  : bypass_out.tlast;

assign decompressor_out.tready = meta.data.compression == COMPRESSION_SNAPPY && out.tready;
assign bypass_out.tready = meta.data.compression == COMPRESSION_RAW && out.tready;


// Decompressor input paused and reset logic
reg [1:0] decompressor_reset_counter;
always_ff @(posedge clk) begin
if (!rst_n) begin
    decompressor_input_paused <= 1'b0;
    decompressor_reset_counter <= 0;
end else begin
    if (decompressor_in.tready && decompressor_in.tvalid && decompressor_in.tlast) begin
        decompressor_input_paused <= 1'b1;
    end else if (decompressor_input_paused && decompressor_out.tready && decompressor_out.tvalid && decompressor_out.tlast) begin
        decompressor_reset_counter <= 2'd2;
    end else if (decompressor_input_paused && decompressor_reset_counter > 0) begin
        if (decompressor_reset_counter == 2'd1) begin
            decompressor_input_paused <= 1'b0;
        end
        decompressor_reset_counter <= decompressor_reset_counter - 1;
    end
end
end

// Snappy decompressor
new_vhsnunzip_wrapper snappy_decompressor (
    .clk(clk),
    .rst_n(rst_n && decompressor_reset_counter == 3'd0),

    .in(decompressor_in),
    .out(decompressor_out)
);

AXISkidBuffer bypass_fifo (
    .clk(clk),
    .rst_n(rst_n),

    .in(bypass_in),
    .out(bypass_out)
);

endmodule
