`include "axi_macros.svh"

import lynxTypes::*;
import reader_pkg::*;

always_comb notify.tie_off_m(); // TODO: add interrupts for config overflows
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();


// Statistics
logic [63:0] cycle_cnt [NUM_UNITS-1:0];
logic [63:0] timer_total [NUM_UNITS-1:0];
logic [63:0] timer_output_stalled [NUM_UNITS-1:0];
logic [63:0] timer_input_stalled [NUM_UNITS-1:0];
logic [63:0] out_chunk_cnt [NUM_UNITS-1:0];
logic [63:0] pages_done_cnt [NUM_UNITS-1:0];

logic [63:0] total_cycle_cnt; 
logic [63:0] total_timer_total;
logic one_core_started;
logic one_core_sending_last;
logic one_core_perf_rst;


logic                  cfg_ready [NUM_UNITS-1:0];
logic                  cfg_valid [NUM_UNITS-1:0];
logic [CONFIG_WIDTH-1:0] cfg_data [NUM_UNITS-1:0];

// Per-unit performance reset from control slave
logic perf_rst [NUM_UNITS-1:0];

// Per-unit hard reset from control slave
logic hard_rst_n [NUM_UNITS-1:0];

(* debug = "yes" *) logic buffer_overflow_flag [NUM_UNITS-1:0];

// Debug signals for top-level ILA (only for unit 0)
logic [2:0] debug_rle_state_0;
logic [2:0] debug_dict_4_state_0;
logic [2:0] debug_dict_8_state_0;

// Per-unit cycle and output counters
genvar u;
generate

  for (u = 0; u < NUM_UNITS; u++) begin : GEN_COUNTERS
    always_ff @(posedge aclk) begin
      if (!aresetn || perf_rst[u]) begin
        cycle_cnt[u]     <= 64'd0;
        timer_total[u]   <= 64'd0;
        timer_output_stalled[u] <= 64'd0;
        timer_input_stalled[u] <= 64'd0;
        out_chunk_cnt[u] <= 64'd0;
      end else begin
        if (cycle_cnt[u] != 64'd0 || axis_host_recv[u].tvalid && axis_host_recv[u].tready) begin
          cycle_cnt[u] <= cycle_cnt[u] + 1;
        end
        if (axis_host_send[u].tready && axis_host_send[u].tvalid) begin
          if (axis_host_send[u].tlast) begin
            timer_total[u] <= cycle_cnt[u];
          end
          out_chunk_cnt[u] <= out_chunk_cnt[u] + 1;
        end
        if (axis_host_send[u].tvalid && !axis_host_send[u].tready) begin
          timer_output_stalled[u] <= timer_output_stalled[u] + 1;
        end
        if (axis_host_recv[u].tvalid && !axis_host_recv[u].tready) begin // Input stalled
          timer_input_stalled[u] <= timer_input_stalled[u] + 1;
        end
      end
    end
  end

  always_ff @(posedge aclk) begin
    if (!aresetn || one_core_perf_rst) begin
      total_cycle_cnt <= 64'd0;
      total_timer_total <= 64'd0;
    end else begin
        if (total_cycle_cnt != 64'd0 || one_core_started) begin
          total_cycle_cnt <= total_cycle_cnt + 1;
        end
        if (one_core_sending_last) begin
            total_timer_total <= total_cycle_cnt;
        end
    end
  end
endgenerate

// Assign one_core_* signals using generate block for array reduction
genvar k;
generate
  if (NUM_UNITS == 1) begin : GEN_SINGLE_UNIT
    assign one_core_started = axis_host_recv[0].tvalid && axis_host_recv[0].tready;
    assign one_core_sending_last = axis_host_send[0].tready && axis_host_send[0].tvalid && axis_host_send[0].tlast;
    assign one_core_perf_rst = perf_rst[0];
  end else begin : GEN_MULTI_UNIT
    logic [NUM_UNITS-1:0] started_temp;
    logic [NUM_UNITS-1:0] sending_temp;
    logic [NUM_UNITS-1:0] perf_rst_temp;
    
    for (k = 0; k < NUM_UNITS; k++) begin : GEN_TEMP_SIGNALS
      assign started_temp[k] = axis_host_recv[k].tvalid && axis_host_recv[k].tready;
      assign sending_temp[k] = axis_host_send[k].tready && axis_host_send[k].tvalid && axis_host_send[k].tlast;
      assign perf_rst_temp[k] = perf_rst[k];
    end
    
    assign one_core_started = |started_temp;
    assign one_core_sending_last = |sending_temp;
    assign one_core_perf_rst = |perf_rst_temp;
  end
endgenerate

genvar i;
generate
  for (i = 0; i < NUM_UNITS; i++) begin : GEN_READERS
    if (i == 0) begin : GEN_READER_0_WITH_DEBUG
      reader_top #(
      ) u_reader (
        .clk(aclk),
        .rst_n(aresetn & hard_rst_n[i]),
        .perf_rst(perf_rst[i]),

        .cfg_ready(cfg_ready[i]),
        .cfg_valid(cfg_valid[i]),
        .cfg_data(cfg_data[i]),

        .in_stream(axis_host_recv[i]),
        .out_stream(axis_host_send[i]),
        .pages_done_count(pages_done_cnt[i]),
        
        .debug_rle_state(debug_rle_state_0),
        .debug_dict_4_state(debug_dict_4_state_0),
        .debug_dict_8_state(debug_dict_8_state_0)
      );
    end else begin : GEN_READER_NO_DEBUG
      reader_top #(
      ) u_reader (
        .clk(aclk),
        .rst_n(aresetn & hard_rst_n[i]),
        .perf_rst(perf_rst[i]),

        .cfg_ready(cfg_ready[i]),
        .cfg_valid(cfg_valid[i]),
        .cfg_data(cfg_data[i]),

        .in_stream(axis_host_recv[i]),
        .out_stream(axis_host_send[i]),
        .pages_done_count(pages_done_cnt[i]),
        
        .debug_rle_state(),
        .debug_dict_4_state(),
        .debug_dict_8_state()
      );
    end
  end
endgenerate

// CSR
ctrl_slv #(
) ctrl_slv (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .timer_total(timer_total),
    .timer_output_stalled(timer_output_stalled),
    .timer_input_stalled(timer_input_stalled),
    .out_chunk_cnt(out_chunk_cnt),
    .pages_done_cnt(pages_done_cnt),
    .buffer_overflow_flag(buffer_overflow_flag),

    .total_timer_total(total_timer_total),

    .cfg_ready_from_stage(cfg_ready),
    .cfg_valid_out(cfg_valid),
    .cfg_data_out(cfg_data),
    .perf_rst(perf_rst),
    .hard_rst_n(hard_rst_n)
);



// ==================== ILA Debug Core ====================

// Top-level ILA - monitors overall input/output streams, performance metrics, and reader states
// ila_top ila_top_inst (
//     .clk(aclk),

//     // Top-level input/output streams
//     .probe0(axis_host_recv[0].tdata),
//     .probe1(axis_host_recv[0].tvalid),
//     .probe2(axis_host_recv[0].tready),
//     .probe3(axis_host_recv[0].tlast),

//     .probe4(axis_host_send[0].tdata),
//     .probe5(axis_host_send[0].tvalid),
//     .probe6(axis_host_send[0].tready),
//     .probe7(axis_host_send[0].tlast),

//     // Performance metrics
//     .probe8(cycle_cnt[0]),
//     .probe9(out_chunk_cnt[0]),
//     .probe10(timer_total[0]),
//     .probe11(timer_output_stalled[0]),
//     .probe12(pages_done_cnt[0]),
    
//     // Control and reader state signals
//     .probe13({buffer_overflow_flag[0], hard_rst_n[0], perf_rst[0], cfg_valid[0], cfg_ready[0]}),
//     .probe14({debug_dict_8_state_0, debug_dict_4_state_0, debug_rle_state_0}),
//     .probe15(cfg_data[0])
// );