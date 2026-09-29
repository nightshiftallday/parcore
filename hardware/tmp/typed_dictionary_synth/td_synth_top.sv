`timescale 1ns / 1ps

import libstf::*;

// Flat-port wrapper for out-of-context synthesis of TypedDictionary (VARIANT 0, inline id
// conversion) or TypedDictionaryITC (VARIANT 1, IndexTypeConverter). Every interface signal is
// routed to a top-level port, so none of them can be optimized away as unused. All ports are
// registered, which bounds every path by flip-flops and keeps the timing report on the dictionary
// instead of on unconstrained I/O. The port registers are not a functional pipeline: registering
// ready changes the handshake timing and is only acceptable because this wrapper is never simulated.
module td_synth_top #(
    parameter int VARIANT       = 0,
    parameter int ID_BITS       = 18,
    parameter int NUM_ELEMENTS  = 16,
    parameter int DATABEAT_SIZE = 64
) (
    input  logic                                 clk,
    input  logic                                 rst_n,

    input  logic [DATABEAT_SIZE-1:0][7:0]        in_values_data,
    input  logic [$bits(type_t)-1:0]             in_values_typ,
    input  logic [DATABEAT_SIZE-1:0]             in_values_keep,
    input  logic                                 in_values_last,
    input  logic                                 in_values_valid,
    output logic                                 in_values_ready,

    input  logic [NUM_ELEMENTS-1:0][ID_BITS-1:0] in_ids_data,
    input  logic [NUM_ELEMENTS-1:0]              in_ids_keep,
    input  logic                                 in_ids_last,
    input  logic                                 in_ids_valid,
    output logic                                 in_ids_ready,

    output logic [DATABEAT_SIZE-1:0][7:0]        out_data,
    output logic [$bits(type_t)-1:0]             out_typ,
    output logic [DATABEAT_SIZE-1:0]             out_keep,
    output logic                                 out_last,
    output logic                                 out_valid,
    input  logic                                 out_ready
);

typedef logic [ID_BITS-1:0] id_t;

logic rst_n_q;

typed_ndata_i #(DATABEAT_SIZE)      in_values (.clk(clk), .rst_n(rst_n_q));
ndata_i       #(id_t, NUM_ELEMENTS) in_ids    (.clk(clk), .rst_n(rst_n_q));
typed_ndata_i #(DATABEAT_SIZE)      out       (.clk(clk), .rst_n(rst_n_q));

always_ff @(posedge clk) begin
    rst_n_q         <= rst_n;

    in_values.data  <= in_values_data;
    in_values.typ   <= type_t'(in_values_typ);
    in_values.keep  <= in_values_keep;
    in_values.last  <= in_values_last;
    in_values.valid <= in_values_valid;
    in_values_ready <= in_values.ready;

    in_ids.data     <= in_ids_data;
    in_ids.keep     <= in_ids_keep;
    in_ids.last     <= in_ids_last;
    in_ids.valid    <= in_ids_valid;
    in_ids_ready    <= in_ids.ready;

    out_data        <= out.data;
    out_typ         <= out.typ;
    out_keep        <= out.keep;
    out_last        <= out.last;
    out_valid       <= out.valid;
    out.ready       <= out_ready;
end

if (VARIANT == 0) begin : gen_inline
    (* keep_hierarchy = "yes" *)
    TypedDictionary #(
        .id_t          (id_t),
        .DATABEAT_SIZE (DATABEAT_SIZE),
        .NUM_ELEMENTS  (NUM_ELEMENTS)
    ) inst_dut (
        .clk       (clk),
        .rst_n     (rst_n_q),
        .in_values (in_values),
        .in_ids    (in_ids),
        .out       (out)
    );
end else begin : gen_itc
    (* keep_hierarchy = "yes" *)
    TypedDictionaryITC #(
        .id_t          (id_t),
        .DATABEAT_SIZE (DATABEAT_SIZE),
        .NUM_ELEMENTS  (NUM_ELEMENTS)
    ) inst_dut (
        .clk       (clk),
        .rst_n     (rst_n_q),
        .in_values (in_values),
        .in_ids    (in_ids),
        .out       (out)
    );
end

endmodule
