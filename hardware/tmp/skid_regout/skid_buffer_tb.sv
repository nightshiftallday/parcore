`timescale 1ns / 1ps

// Checks a SkidBuffer implementation: no loss or reordering under random valid/ready, no bubble
// while it holds data, full streaming throughput, its capacity under a stall, and whether any
// output reacts combinationally to an input (in.ready to out.ready, out.valid/out.data to
// in.valid/in.data), i.e. whether it cuts long ready/valid chains in both directions.
module skid_buffer_tb;

localparam int NUM_RANDOM_CYCLES = 20000;
localparam int NUM_STREAM_CYCLES = 1000;

typedef logic [31:0] data_t;

logic clk = 0;
logic rst_n = 0;
always #2 clk = ~clk;

ready_valid_i #(data_t) in (.*);
ready_valid_i #(data_t) out (.*);

SkidBuffer #(.data_t(data_t)) dut (.clk(clk), .rst_n(rst_n), .in(in), .out(out));

int    num_errors = 0;
data_t next_in = 0, next_out = 0;
int    num_in = 0, num_out = 0;
int    ready_comb = 0, valid_comb = 0, data_comb = 0, bubbles = 0;
int    cycle_count = 0;
// Order-sensitive hash of the cycles with an output handshake; equal hashes for two
// implementations under the same stimulus mean their handshakes are cycle-for-cycle identical.
longint unsigned out_trace = 0;

// -- Scoreboard (values sampled before the edge updates the buffer) --------------------------------
always @(posedge clk) begin
    if (rst_n) begin
        cycle_count++;
        if (num_in > num_out && !out.valid) bubbles++;
        if (out.valid && out.ready) out_trace = out_trace * 1000003 + cycle_count;
        if (in.valid && in.ready) begin
            next_in++;
            num_in++;
        end
        if (out.valid && out.ready) begin
            if (out.data !== next_out) begin
                $error("output %0d: got %0d, expected %0d", num_out, out.data, next_out);
                num_errors++;
            end
            next_out++;
            num_out++;
        end
    end
end

// -- Combinational path probes, between the negative edge and the next positive edge ---------------
task automatic probe();
    logic  r, v;
    data_t d;
    #0.5;
    r = in.ready;
    out.ready = ~out.ready;
    #0.1;
    if (in.ready !== r) ready_comb++;
    out.ready = ~out.ready;
    #0.1;
    v = out.valid;
    d = out.data;
    in.valid = ~in.valid;
    in.data  = ~in.data;
    #0.1;
    if (out.valid !== v) valid_comb++;
    if (out.data !== d) data_comb++;
    in.valid = ~in.valid;
    in.data  = ~in.data;
    #0.1;
endtask

task automatic cycle(logic valid, logic ready);
    @(negedge clk);
    in.valid  = valid;
    in.data   = next_in;
    out.ready = ready;
    probe();
endtask

initial begin
    int start, accepted;

    // The default per-process seed depends on the elaborated design, which differs between
    // implementations, so the stimulus is seeded explicitly.
    process::self().srandom(1);
    in.valid  = 1'b0;
    out.ready = 1'b0;
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (2) @(posedge clk);

    repeat (NUM_RANDOM_CYCLES) cycle($urandom_range(0, 9) < 7, $urandom_range(0, 9) < 6);
    repeat (10) cycle(1'b0, 1'b1);

    start = num_out;
    repeat (NUM_STREAM_CYCLES) cycle(1'b1, 1'b1);
    $display("STREAM %0d beats out in %0d cycles", num_out - start, NUM_STREAM_CYCLES);
    // Only NUM_STREAM_CYCLES - 1 edges have passed when cycle() returns, and the first beat
    // takes one of them to reach the output, so full throughput is NUM_STREAM_CYCLES - 2 beats.
    if (num_out - start < NUM_STREAM_CYCLES - 2) begin
        $error("streaming throughput below 1 beat per cycle");
        num_errors++;
    end

    accepted = num_in;
    repeat (10) cycle(1'b1, 1'b0);
    $display("CAPACITY %0d beats accepted during a 10-cycle stall", num_in - accepted);
    repeat (20) cycle(1'b0, 1'b1);

    if (num_in != num_out) begin
        $error("%0d beats in, %0d beats out", num_in, num_out);
        num_errors++;
    end
    $display("COMB in.ready<-out.ready %0d, out.valid<-in.valid %0d, out.data<-in.data %0d",
             ready_comb, valid_comb, data_comb);
    $display("BUBBLES %0d cycles with data held but out.valid low", bubbles);
    $display("TRACE %0d output handshakes, hash %h", num_out, out_trace);
    if (bubbles != 0) num_errors++;

    if (num_errors == 0) $display("PASS: %0d beats", num_out);
    else                 $display("FAIL: %0d errors, %0d beats", num_errors, num_out);
    $finish;
end

endmodule
