`timescale 1ns / 1ps

import libstf::*;

// Drives TypedDictionary (inline ID conversion) or, with +define+DUT_ITC, TypedDictionaryITC
// (IndexTypeConverter) with the same pre-generated dictionaries and id streams, checks every output
// beat and reports the cycles each id phase takes. With +define+DUT_TD2 it drives libstf's
// TypedDictionary2 instead, which takes untyped values and ids tagged with the type.
// +define+NO_FLOAT replaces FLOAT_T by INT32_T in the generated dictionaries.
//
// Plusargs: +NOSTALL disables the random input gaps and output backpressure, so the cycle counts
// reflect the pipeline alone. +CSV=<file> writes one line of per-dictionary metrics per dictionary.
module typed_dictionary_tb;

localparam int NUM_ELEMENTS  = 16;
localparam int DATABEAT_SIZE = 64;
localparam int NUM_RANDOM    = 24;
// A dictionary takes a few hundred cycles; xsim runs this design at roughly 100 cycles per second,
// so a larger timeout makes a deadlock take a long time to report.
localparam int TIMEOUT       = 5000;
localparam int SEED          = 1;

// Matches dict_id_t of libstf/hardware/unit-tests/vfpga_tops/typed_dict_test.sv.
typedef logic [17:0] id_t;
typedef logic [31:0] word_t;

typedef struct {
    word_t                     data[NUM_ELEMENTS];
    logic [NUM_ELEMENTS - 1:0] keep;
    logic                      last;
    type_t                     typ;
} beat_t;

class dict_c;
    type_t typ;
    word_t words[$];
    int    ids[$];
endclass

logic clk = 0;
logic rst_n = 0;
always #2 clk = ~clk;

`ifdef DUT_TD2
ndata_i       #(data8_t, DATABEAT_SIZE) in_values (.*);
typed_ndata_i #(NUM_ELEMENTS, id_t)     in_ids    (.*);
`define CONV_IDS dut.untyped_ids
`else
typed_ndata_i #(DATABEAT_SIZE)      in_values (.*);
ndata_i       #(id_t, NUM_ELEMENTS) in_ids    (.*);
`define CONV_IDS dut.dictionary_in_ids
`endif
typed_ndata_i #(DATABEAT_SIZE)     out       (.*);

`ifdef DUT_TD2
localparam string VARIANT = "td2";
TypedDictionary2 #(
`elsif DUT_ITC
localparam string VARIANT = "itc";
TypedDictionaryITC #(
`else
localparam string VARIANT = "inline";
TypedDictionary #(
`endif
    .id_t          (id_t),
    .DATABEAT_SIZE (DATABEAT_SIZE),
    .NUM_ELEMENTS  (NUM_ELEMENTS)
) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_values (in_values),
    .in_ids    (in_ids),
    .out       (out)
);

`ifdef NO_FLOAT
const type_t TYPES[4] = '{INT32_T, INT32_T, INT64_T, DOUBLE_T};
`else
const type_t TYPES[4] = '{INT32_T, FLOAT_T, INT64_T, DOUBLE_T};
`endif

bit    no_stall;
dict_c dicts[$];
beat_t expected[$];
int    num_errors = 0;
int    num_out_beats = 0;

// -- Cycle bookkeeping ----------------------------------------------------------------------------
longint cycle = 0;
always @(posedge clk) cycle++;

longint first_id_hs, last_id_hs, first_conv_hs, last_conv_hs, first_out_hs, last_out_hs;
int     num_id_hs, num_conv_hs, num_out_hs, id_stall_cycles;

task automatic reset_metrics();
    first_id_hs = -1; first_conv_hs = -1; first_out_hs = -1;
    num_id_hs = 0; num_conv_hs = 0; num_out_hs = 0; id_stall_cycles = 0;
endtask

always @(posedge clk) begin
    if (rst_n) begin
        if (in_ids.valid && in_ids.ready) begin
            if (first_id_hs < 0) first_id_hs = cycle;
            last_id_hs = cycle;
            num_id_hs++;
        end
        if (in_ids.valid && !in_ids.ready) id_stall_cycles++;
        if (`CONV_IDS.valid && `CONV_IDS.ready) begin
            if (first_conv_hs < 0) first_conv_hs = cycle;
            last_conv_hs = cycle;
            num_conv_hs++;
        end
        if (out.valid && out.ready) begin
            if (first_out_hs < 0) first_out_hs = cycle;
            last_out_hs = cycle;
            num_out_hs++;
        end
    end
end

// A deadlock can also stop the value or id senders, which wait for ready without a timeout, so the
// run ends once no interface has completed a handshake for TIMEOUT cycles.
longint last_activity = 0;
always @(posedge clk) begin
    if (!rst_n || (in_values.valid && in_values.ready) || (in_ids.valid && in_ids.ready) ||
        (out.valid && out.ready))
        last_activity = cycle;
    else if (cycle - last_activity > TIMEOUT) begin
        $error("deadlock: no handshake for %0d cycles at cycle %0d", TIMEOUT, cycle);
        $display("DEADLOCK in_values valid=%b ready=%b | in_ids valid=%b ready=%b | out valid=%b ready=%b",
                 in_values.valid, in_values.ready, in_ids.valid, in_ids.ready, out.valid, out.ready);
        $display("DEADLOCK conv_ids valid=%b ready=%b last=%b | dut.typ valid=%b data=%s | expected beats %0d",
                 `CONV_IDS.valid, `CONV_IDS.ready, `CONV_IDS.last, dut.typ.valid, dut.typ.data.name(),
                 expected.size());
        $display("FAIL: %s, deadlock after %0d output beats", VARIANT, num_out_beats);
        $finish;
    end
end

// -- Stimulus -------------------------------------------------------------------------------------
function automatic int factor_of(type_t t);
    return GET_TYPE_WIDTH(t) / 32;
endfunction

function automatic dict_c make_dict(type_t typ, int num_values, int num_ids, bit sequential);
    dict_c d = new();
    d.typ = typ;
    repeat (num_values * factor_of(typ)) d.words.push_back($urandom);
    for (int i = 0; i < num_ids; i++)
        d.ids.push_back(sequential ? i % num_values : $urandom_range(0, num_values - 1));
    return d;
endfunction

function automatic void push_expected(dict_c d);
    int f = factor_of(d.typ);
    int s = NUM_ELEMENTS / f;
    for (int base = 0; base < d.ids.size(); base += NUM_ELEMENTS) begin
        int kept = d.ids.size() - base < NUM_ELEMENTS ? d.ids.size() - base : NUM_ELEMENTS;
        int beats = (kept + s - 1) / s;
        for (int j = 0; j < beats; j++) begin
            beat_t e;
            e.typ  = d.typ;
            e.last = base + NUM_ELEMENTS >= d.ids.size() && j == beats - 1;
            for (int i = 0; i < NUM_ELEMENTS; i++) begin
                int src = j * s + i / f;
                e.keep[i] = src < kept;
                e.data[i] = src < kept ? d.words[d.ids[base + src] * f + i % f] : 'x;
            end
            expected.push_back(e);
        end
    end
endfunction

task automatic gap();
    if (!no_stall) while ($urandom_range(0, 3) == 0) @(posedge clk);
endtask

task automatic send_values(dict_c d);
    for (int base = 0; base < d.words.size(); base += NUM_ELEMENTS) begin
        for (int i = 0; i < NUM_ELEMENTS; i++) begin
            bit kept = base + i < d.words.size();
            for (int b = 0; b < 4; b++) begin
                in_values.data[i * 4 + b] <= kept ? d.words[base + i][b * 8 +: 8] : 8'hxx;
                in_values.keep[i * 4 + b] <= kept;
            end
        end
`ifndef DUT_TD2
        in_values.typ   <= d.typ;
`endif
        in_values.last  <= base + NUM_ELEMENTS >= d.words.size();
        in_values.valid <= 1'b1;
        do @(posedge clk); while (!in_values.ready);
        in_values.valid <= 1'b0;
        gap();
    end
endtask

task automatic send_ids(dict_c d);
    for (int base = 0; base < d.ids.size(); base += NUM_ELEMENTS) begin
        for (int i = 0; i < NUM_ELEMENTS; i++) begin
            bit kept = base + i < d.ids.size();
            in_ids.data[i] <= kept ? id_t'(d.ids[base + i]) : 'x;
            in_ids.keep[i] <= kept;
        end
`ifdef DUT_TD2
        in_ids.typ   <= d.typ;
`endif
        in_ids.last  <= base + NUM_ELEMENTS >= d.ids.size();
        in_ids.valid <= 1'b1;
        do @(posedge clk); while (!in_ids.ready);
        in_ids.valid <= 1'b0;
        gap();
    end
endtask

// -- Checking -------------------------------------------------------------------------------------
always_ff @(posedge clk) begin
    if (!rst_n) out.ready <= 1'b0;
    else        out.ready <= no_stall || $urandom_range(0, 3) != 0;
end

always @(posedge clk) begin
    if (rst_n && out.valid && out.ready) begin
        beat_t e;
        num_out_beats++;
        if (expected.size() == 0) begin
            $error("output beat %0d without expected beat", num_out_beats);
            num_errors++;
        end else begin
            logic [DATABEAT_SIZE - 1:0] keep;
            e = expected.pop_front();
            for (int i = 0; i < DATABEAT_SIZE; i++) keep[i] = e.keep[i / 4];
            if (out.keep !== keep || out.last !== e.last || out.typ !== e.typ) begin
                $error("beat %0d: keep %h/%h last %b/%b typ %s/%s (got/expected)", num_out_beats,
                       out.keep, keep, out.last, e.last, out.typ.name(), e.typ.name());
                num_errors++;
            end
            for (int i = 0; i < NUM_ELEMENTS; i++) begin
                word_t got = {out.data[i * 4 + 3], out.data[i * 4 + 2], out.data[i * 4 + 1],
                              out.data[i * 4]};
                if (e.keep[i] && got !== e.data[i]) begin
                    $error("beat %0d lane %0d: data %h, expected %h", num_out_beats, i, got,
                           e.data[i]);
                    num_errors++;
                end
            end
        end
    end
end

// -- Test sequence --------------------------------------------------------------------------------
initial begin
    string  csv_path;
    int     csv = 0;
    longint sum_cycles[2], sum_conv_cycles[2], sum_id_beats[2], sum_latency[2], sum_stalls[2];
    int     num_dicts[2];

    no_stall = $test$plusargs("NOSTALL");
    if ($value$plusargs("CSV=%s", csv_path)) begin
        csv = $fopen(csv_path, "w");
        $fdisplay(csv, "variant,dict,typ,num_values,num_ids,id_beats,conv_beats,out_beats,",
                  "conv_cycles,id_phase_cycles,first_out_latency,id_stall_cycles");
    end

    // All stimulus is drawn before the first clock from an explicitly seeded generator, so both
    // variants see the same dictionaries (the default per-process seed depends on the elaborated
    // design, which differs between the variants).
    process::self().srandom(SEED);
    foreach (TYPES[t]) begin
        dicts.push_back(make_dict(TYPES[t], 500, 500, 1));
        dicts.push_back(make_dict(TYPES[t], 500, 1001, 0));
    end
    dicts.push_back(make_dict(INT64_T, 3, 1, 0));
    dicts.push_back(make_dict(INT32_T, 1, 8, 0));
    dicts.push_back(make_dict(DOUBLE_T, 17, 9, 0));
    dicts.push_back(make_dict(FLOAT_T, 17, 17, 0));
    for (int n = 0; n < NUM_RANDOM; n++)
        dicts.push_back(make_dict(TYPES[$urandom_range(0, 3)], $urandom_range(1, 800),
                                  $urandom_range(1, 1200), 0));

    in_values.valid = 1'b0;
    in_ids.valid    = 1'b0;
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (20) @(posedge clk);

    foreach (dicts[n]) begin
        dict_c d = dicts[n];
        int    w = factor_of(d.typ) - 1;
        longint conv_cycles, id_cycles, latency;

        reset_metrics();
        push_expected(d);
        send_values(d);
        send_ids(d);
        fork
            wait (expected.size() == 0);
            begin
                repeat (TIMEOUT) @(posedge clk);
                $error("dict %0d: timeout with %0d expected beats outstanding", n, expected.size());
                num_errors++;
            end
        join_any
        disable fork;
        if (expected.size() != 0) break;
        @(posedge clk);

        conv_cycles = last_conv_hs - first_id_hs + 1;
        id_cycles   = last_out_hs - first_id_hs + 1;
        latency     = first_out_hs - first_id_hs;
        sum_cycles[w]      += id_cycles;
        sum_conv_cycles[w] += conv_cycles;
        sum_id_beats[w]    += num_id_hs;
        sum_latency[w]     += latency;
        sum_stalls[w]      += id_stall_cycles;
        num_dicts[w]++;
        if (csv)
            $fdisplay(csv, "%s,%0d,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d", VARIANT, n,
                      d.typ.name(), d.words.size() / factor_of(d.typ), d.ids.size(), num_id_hs,
                      num_conv_hs, num_out_hs, conv_cycles, id_cycles, latency, id_stall_cycles);
        if (csv) $fflush(csv);
        repeat (5) @(posedge clk);
    end

    if (csv) $fclose(csv);
    for (int w = 0; w < 2; w++)
        $display("SUMMARY variant=%s width=%0d dicts=%0d id_beats=%0d conv_cycles=%0d ",
                 VARIANT, 32 * (w + 1), num_dicts[w], sum_id_beats[w], sum_conv_cycles[w],
                 "id_phase_cycles=%0d sum_first_out_latency=%0d id_stall_cycles=%0d",
                 sum_cycles[w], sum_latency[w], sum_stalls[w]);

    if (num_errors == 0)
        $display("PASS: %s, %0d dictionaries, %0d output beats", VARIANT, dicts.size(),
                 num_out_beats);
    else
        $display("FAIL: %s, %0d errors (%0d output beats)", VARIANT, num_errors, num_out_beats);
    $finish;
end

endmodule
