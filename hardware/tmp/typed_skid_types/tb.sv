`timescale 1ns / 1ps

import libstf::*;

// Two TypedNDataSkidBuffers chained through a local interface, reached through this module's
// interface ports, as TypedDictionary2 uses them.
module wrap #(
    parameter int  N,
    parameter type T
) (
    input logic clk,
    input logic rst_n,

    typed_ndata_i.s in,
    typed_ndata_i.m out
);

typed_ndata_i #(N, T) mid (.clk(clk), .rst_n(rst_n));

TypedNDataSkidBuffer #(.DATABEAT_SIZE(N)) inst_first  (.clk(clk), .rst_n(rst_n), .in(in),  .out(mid));
TypedNDataSkidBuffer #(.DATABEAT_SIZE(N)) inst_second (.clk(clk), .rst_n(rst_n), .in(mid), .out(out));

endmodule

// Random valid/ready traffic through one TypedNDataSkidBuffer with element type T (WRAP = 0) or
// through wrap (WRAP = 1), checking data, typ, keep and last of every beat in order.
module harness #(
    parameter int  N,
    parameter type T,
    parameter bit  WRAP,
    parameter int  NUM_BEATS = 2000
) (
    input  logic clk,
    input  logic rst_n,
    output logic done,
    output int   num_errors
);

typedef struct packed {
    T [N - 1:0]     data;
    type_t          typ;
    logic [N - 1:0] keep;
    logic           last;
} beat_t;

typed_ndata_i #(N, T) in  (.clk(clk), .rst_n(rst_n));
typed_ndata_i #(N, T) out (.clk(clk), .rst_n(rst_n));

if (WRAP) begin : gen_wrap
    wrap #(.N(N), .T(T)) dut (.clk(clk), .rst_n(rst_n), .in(in), .out(out));
end else begin : gen_direct
    TypedNDataSkidBuffer #(.DATABEAT_SIZE(N)) dut (.clk(clk), .rst_n(rst_n), .in(in), .out(out));
end

beat_t sent[$];
beat_t next_beat;
int    num_sent = 0, num_received = 0;

function automatic beat_t random_beat();
    beat_t b;
    b = {$urandom, $urandom, $urandom, $urandom, $urandom, $urandom};
    b.typ = type_t'($urandom_range(0, 5));
    return b;
endfunction

initial begin
    num_errors = 0;
    done = 1'b0;
    in.valid = 1'b0;
    out.ready = 1'b0;
    next_beat = random_beat();
    wait (rst_n);
    while (num_received < NUM_BEATS) begin
        @(negedge clk);
        in.valid  = num_sent < NUM_BEATS && $urandom_range(0, 3) != 0;
        {in.data, in.typ, in.keep, in.last} = next_beat;
        out.ready = $urandom_range(0, 2) != 0;
    end
    done = 1'b1;
end

always @(posedge clk) begin
    if (rst_n) begin
        if (in.valid && in.ready) begin
            sent.push_back(next_beat);
            next_beat = random_beat();
            num_sent++;
        end
        if (out.valid && out.ready) begin
            beat_t e = sent.pop_front();
            if ({out.data, out.typ, out.keep, out.last} !== e) begin
                $error("%m beat %0d: got %h, expected %h", num_received,
                       {out.data, out.typ, out.keep, out.last}, e);
                num_errors++;
            end
            num_received++;
        end
    end
end

endmodule

module tb;

typedef logic [17:0] id_t;

typedef struct packed {
    logic [7:0] a;
    logic [4:0] b;
} pair_t;

logic clk = 0;
logic rst_n = 0;
always #2 clk = ~clk;

logic done_id, done_pair;
int   errors_id, errors_pair;

`ifdef WRAP
localparam bit WRAP = 1;
`else
localparam bit WRAP = 0;
`endif

harness #(.N(4), .T(id_t), .WRAP(WRAP))   h_id   (.clk(clk), .rst_n(rst_n), .done(done_id),   .num_errors(errors_id));
harness #(.N(3), .T(pair_t), .WRAP(WRAP)) h_pair (.clk(clk), .rst_n(rst_n), .done(done_pair), .num_errors(errors_pair));

initial begin
    process::self().srandom(1);
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    fork
        wait (done_id && done_pair);
        begin
            repeat (100000) @(posedge clk);
            $error("timeout");
        end
    join_any
    if (done_id && done_pair && errors_id == 0 && errors_pair == 0)
        $display("PASS: id and struct element types");
    else
        $display("FAIL: %0d/%0d errors (id/struct), done %b/%b", errors_id, errors_pair, done_id,
                 done_pair);
    $finish;
end

endmodule
