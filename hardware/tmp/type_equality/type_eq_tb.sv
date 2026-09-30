`timescale 1ns / 1ps

`include "libstf_macros.svh"

import libstf::*;

// Checks how type(A) == type(B) and $typename(A) == $typename(B) evaluate for pairs of type
// parameters, and whether they work as an elaboration-time assertion (+define+FIRE makes one
// ASSERT_ELAB fail on purpose).
module type_pair #(
    parameter type A,
    parameter type B,
    parameter bit  EXPECT
) ();

localparam bit EQ_TYPE = type(A) == type(B);
localparam bit EQ_NAME = $typename(A) == $typename(B);

if (EXPECT) begin : gen_assert
    `ASSERT_ELAB(type(A) == type(B))
end

// Elaboration-time report, so tools that do not simulate (Vivado synthesis) show the values too.
if (1) begin : gen_report
    $info("ELAB type()==%0d $typename==%0d expected=%0d", EQ_TYPE, EQ_NAME, EXPECT);
end

initial $display("CASE %-40s type()==%0d $typename==%0d expected=%0d %s", $sformatf("%m"), EQ_TYPE,
                 EQ_NAME, EXPECT, EQ_TYPE == EXPECT ? "ok" : "WRONG");

endmodule

// The element type of an interface port compared with the module's own type parameter, the way a
// module would check that it was connected to the interface it expects.
module port_type_check #(
    parameter type data_t,
    parameter bit  EXPECT
) (
    typed_ndata_i.s in
);

localparam type port_data_t = in.data_t;
localparam bit  EQ = type(port_data_t) == type(data_t);

`ASSERT_ELAB(!EXPECT || type(port_data_t) == type(data_t))

if (1) begin : gen_report
    $info("ELAB port type()==%0d expected=%0d", EQ, EXPECT);
end

initial $display("CASE %-40s type()==%0d expected=%0d %s", $sformatf("%m"), EQ, EXPECT,
                 EQ == EXPECT ? "ok" : "WRONG");

endmodule

module port_wrap #(
    parameter type data_t,
    parameter bit  EXPECT
) (
    typed_ndata_i.s in
);

port_type_check #(.data_t(data_t), .EXPECT(EXPECT)) inst (.in(in));

endmodule

module type_eq_tb;

typedef logic [17:0]        id_t;
typedef id_t                id_alias_t;
typedef struct packed {
    logic [7:0] a;
    logic [9:0] b;
} pair_t;

logic clk = 0, rst_n = 0;

type_pair #(logic [17:0], logic [17:0], 1)        same_logic ();
type_pair #(id_t, logic [17:0], 1)                typedef_vs_logic ();
type_pair #(id_alias_t, id_t, 1)                  alias_vs_typedef ();
type_pair #(pair_t, pair_t, 1)                    same_struct ();
type_pair #(logic [17:0], logic [31:0], 0)        different_width ();
type_pair #(pair_t, logic [17:0], 0)              struct_vs_logic ();
type_pair #(bit [17:0], logic [17:0], 0)          bit_vs_logic ();
type_pair #(logic signed [17:0], logic [17:0], 0) signed_vs_unsigned ();
type_pair #(logic [0:17], logic [17:0], 0)        ascending_range ();
type_pair #(int, logic signed [31:0], 0)          int_vs_logic32 ();

typed_ndata_i #(4, id_t)   ids   (.*);
typed_ndata_i #(4, pair_t) pairs (.*);

port_type_check #(.data_t(id_t), .EXPECT(1))         port_local_same (.in(ids));
port_type_check #(.data_t(logic [31:0]), .EXPECT(0)) port_local_diff (.in(ids));
port_wrap       #(.data_t(id_t), .EXPECT(1))         port_chained_same (.in(ids));
port_wrap       #(.data_t(id_t), .EXPECT(0))         port_chained_struct (.in(pairs));

`ifdef FIRE
type_pair #(logic [17:0], logic [31:0], 1) must_fail ();
`endif

initial begin
    #1 $display("DONE");
    $finish;
end

endmodule
