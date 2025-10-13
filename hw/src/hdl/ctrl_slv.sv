`timescale 1ns / 1ps

import lynxTypes::*;
import reader_pkg::*;

module ctrl_slv #(
    parameter CTRL_SLV_BUFFER_DEPTH = 512,
    parameter BUFFER_ADDR_WIDTH = $clog2(CTRL_SLV_BUFFER_DEPTH),
    parameter HARD_RESET_CYCLES = 16
)(
  input  logic aclk,
  input  logic aresetn,
  
  AXI4L.s axi_ctrl,

  input logic [63:0] timer_total [NUM_UNITS - 1 : 0],
  input logic [63:0] timer_output_stalled [NUM_UNITS - 1 : 0],
  input logic [63:0] timer_input_stalled [NUM_UNITS - 1 : 0],
  input logic [63:0] out_chunk_cnt [NUM_UNITS - 1 : 0],
  input logic [63:0] pages_done_cnt [NUM_UNITS - 1 : 0],

  input logic [63:0] total_timer_total,

  // Ready signal from each unit
  input  logic                  cfg_ready_from_stage [NUM_UNITS - 1 : 0],

  // Output to stages
  output logic                  cfg_valid_out [NUM_UNITS - 1 : 0],
  output logic [CONFIG_WIDTH-1:0] cfg_data_out [NUM_UNITS - 1 : 0],
  (* debug = "yes" *) output logic buffer_overflow_flag [NUM_UNITS - 1 : 0],

  // Performance counter reset (per unit, one-cycle pulse)
  output logic perf_rst [NUM_UNITS - 1 : 0],

  // Hard reset (per unit, active low)
  output logic hard_rst_n [NUM_UNITS - 1 : 0]

);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------
// Constants
localparam integer N_REGS_PER_UNIT = 16;
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS / 8);  // 3 for 64-bit AXI
localparam integer UNIT_ADDR_BITS = (NUM_UNITS == 1) ? 1 : $clog2(NUM_UNITS);
localparam integer REG_ADDR_BITS = $clog2(N_REGS_PER_UNIT);
localparam integer AXI_ADDR_BITS = ADDR_LSB + REG_ADDR_BITS + UNIT_ADDR_BITS;

// Internal registers
logic [AXI_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXI_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;

// For single unit, always select unit 0; for multiple units, decode from address
wire [UNIT_ADDR_BITS-1:0] unit_sel = (NUM_UNITS == 1) ? 0 : axi_awaddr[ADDR_LSB + REG_ADDR_BITS +: UNIT_ADDR_BITS];
wire [REG_ADDR_BITS-1:0] reg_sel  = axi_awaddr[ADDR_LSB +: REG_ADDR_BITS];

logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// Internal ring buffer
logic [CONFIG_WIDTH-1:0] buffer [NUM_UNITS-1:0] [CTRL_SLV_BUFFER_DEPTH-1:0];
logic [BUFFER_ADDR_WIDTH:0] wr_ptr [NUM_UNITS-1:0];
logic [BUFFER_ADDR_WIDTH:0] rd_ptr [NUM_UNITS-1:0];
logic [BUFFER_ADDR_WIDTH:0] wr_ptr_p1 [NUM_UNITS-1:0];
logic [BUFFER_ADDR_WIDTH:0] available_space [NUM_UNITS-1:0];
logic buffer_full [NUM_UNITS-1:0];
logic buffer_empty [NUM_UNITS-1:0];
logic broadcast_ready [NUM_UNITS-1:0];

// Hard reset logic
logic [$clog2(HARD_RESET_CYCLES+1)-1:0] hard_reset_counter [NUM_UNITS-1:0];
logic hard_reset_active [NUM_UNITS-1:0];

genvar u;
generate
    for (u = 0; u < NUM_UNITS; u = u + 1) begin : gen_buffer_logic
        assign wr_ptr_p1[u]        = (wr_ptr[u] + 1) % CTRL_SLV_BUFFER_DEPTH;
        assign buffer_full[u]      = (wr_ptr_p1[u] == rd_ptr[u]);
        assign buffer_empty[u]     = (wr_ptr[u] == rd_ptr[u]);
        assign available_space[u]  = (wr_ptr[u] >= rd_ptr[u]) ? 
                                    (CTRL_SLV_BUFFER_DEPTH - (wr_ptr[u] - rd_ptr[u])) : 
                                    (rd_ptr[u] - wr_ptr[u]);

        // All stages of this unit ready
        assign broadcast_ready[u]  = cfg_ready_from_stage[u];

        // Valid/data outputs for this unit
        assign cfg_valid_out[u]    = !buffer_empty[u];
        assign cfg_data_out[u]     = buffer[u][rd_ptr[u]];
        
        // Hard reset output (active low)
        assign hard_rst_n[u]       = !hard_reset_active[u];
    end
endgenerate

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
localparam integer HARD_RESET_REG = 0;
localparam integer PERF_RESET_REG = 1;
localparam integer CONFIG_WRITE_REG = 2;
localparam integer OVERFLOW_CLR_REG = 3;
// readback registers
localparam integer TIMER_TOTAL_REG = 4;
localparam integer TIMER_OUTPUT_STALLED_REG = 5;
localparam integer TIMER_INPUT_STALLED_REG = 6;
localparam integer OUT_CHUNK_CNT_REG = 7;
localparam integer PAGES_DONE_CNT_REG = 8;

localparam integer TOTAL_TIMER_TOTAL_REG = 9;

// Write process
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if (aresetn) begin
    // Default clear perf reset pulses
    for (int u = 0; u < NUM_UNITS; u++) begin
      perf_rst[u] <= 1'b0;
  
      if (hard_reset_active[u]) begin
        if (hard_reset_counter[u] == HARD_RESET_CYCLES-1) begin
          // Release hard reset after specified cycles
          hard_reset_active[u] <= 1'b0;
          hard_reset_counter[u] <= '0;
        end else begin
          hard_reset_counter[u] <= hard_reset_counter[u] + 1;
        end
      end
    end


    if (slv_reg_wren) begin
      case (reg_sel)
        HARD_RESET_REG: begin
          // Start hard reset for selected unit
          if (axi_ctrl.wstrb[0]) begin
            hard_reset_active[unit_sel] <= 1'b1;
            hard_reset_counter[unit_sel] <= '0;
          end
        end
        PERF_RESET_REG: begin
          // Write any value to pulse perf counter reset for selected unit
          if (axi_ctrl.wstrb[0]) begin
            perf_rst[unit_sel] <= 1'b1;
          end
        end
        CONFIG_WRITE_REG: begin
            if (available_space[unit_sel] < 1) begin
              buffer_overflow_flag[unit_sel] <= 1'b1;
            end else begin
              if (axi_ctrl.wstrb >= (CONFIG_WIDTH/8)) begin
                for (int i = 0; i < (CONFIG_WIDTH/8); i++) begin
                  if(axi_ctrl.wstrb[i]) begin
                    buffer[unit_sel][wr_ptr[unit_sel]][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                  end
                end
                wr_ptr[unit_sel] <= wr_ptr_p1[unit_sel];
              end
            end
        end
        OVERFLOW_CLR_REG: begin
          if (axi_ctrl.wstrb[0]) begin
            buffer_overflow_flag[unit_sel] <= 1'b0;
          end
        end
        default: ;
      endcase
    end





  end else begin
    for (int u = 0; u < NUM_UNITS; u++) begin
      wr_ptr[u]               <= '0;
      buffer_overflow_flag[u] <= 1'b0;
      perf_rst[u]             <= 1'b0;
      hard_reset_active[u]    <= 1'b0;
      hard_reset_counter[u]   <= '0;
    end
  end
end

// Consume config when each unit is ready
always_ff @(posedge aclk) begin
  if (!aresetn) begin
    for (int u = 0; u < NUM_UNITS; u++) begin
      rd_ptr[u] <= '0;
    end
  end else begin
    for (int u = 0; u < NUM_UNITS; u++) begin
      // Consume config when unit is ready and buffer has data
      if (broadcast_ready[u] && cfg_valid_out[u]) begin
        // Prefer compare+wrap instead of % for nicer synthesis
        rd_ptr[u] <= (rd_ptr[u] == CTRL_SLV_BUFFER_DEPTH-1) ? '0 : rd_ptr[u] + 1;
      end
    end
  end
end

// Read process
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

// For single unit, always select unit 0; for multiple units, decode from address  
wire [UNIT_ADDR_BITS-1:0] unit_sel_r = (NUM_UNITS == 1) ? 0 : axi_araddr[ADDR_LSB + REG_ADDR_BITS +: UNIT_ADDR_BITS];
wire [REG_ADDR_BITS-1:0] reg_sel_r  = axi_araddr[ADDR_LSB +: REG_ADDR_BITS];

always_ff @(posedge aclk) begin
  if (aresetn) begin
    if (slv_reg_rden) begin
      axi_rdata <= 0;

      case (reg_sel_r)
        TIMER_TOTAL_REG: 
          axi_rdata[63:0] <= timer_total[unit_sel_r];
  
        TIMER_OUTPUT_STALLED_REG: 
          axi_rdata[63:0] <= timer_output_stalled[unit_sel_r];
        
        TIMER_INPUT_STALLED_REG: 
          axi_rdata[63:0] <= timer_input_stalled[unit_sel_r];
        
        OUT_CHUNK_CNT_REG: 
          axi_rdata[63:0] <= out_chunk_cnt[unit_sel_r];

        PAGES_DONE_CNT_REG:
          axi_rdata[63:0] <= pages_done_cnt[unit_sel_r];

        TOTAL_TIMER_TOTAL_REG: 
          axi_rdata[63:0] <= total_timer_total;
                
        default: ;
      endcase
    end
  end else begin
    axi_rdata <= 0;
  end
end


// Output
// always_comb begin
//   bench_ctrl      = slv_reg[BENCH_CTRL_REG][1:0];
//   bench_vaddr     = slv_reg[BENCH_VADDR_REG][VADDR_BITS-1:0];
//   bench_len       = slv_reg[BENCH_LEN_REG][LEN_BITS-1:0];
//   bench_pid       = slv_reg[BENCH_PID_REG][PID_BITS-1:0];
//   bench_n_reps    = slv_reg[BENCH_N_REPS_REG][31:0];
//   bench_n_beats   = slv_reg[BENCH_N_BEATS_REG];
//   bench_dest      = slv_reg[BENCH_DEST_REG][DEST_BITS-1:0];
// end


// --------------------------------------------------------------------------------------
// AXI CTRL  
// -------------------------------------------------------------------------------------- 
// Don't edit

// I/O
assign axi_ctrl.awready = axi_awready;
assign axi_ctrl.arready = axi_arready;
assign axi_ctrl.bresp = axi_bresp;
assign axi_ctrl.bvalid = axi_bvalid;
assign axi_ctrl.wready = axi_wready;
assign axi_ctrl.rdata = axi_rdata;
assign axi_ctrl.rresp = axi_rresp;
assign axi_ctrl.rvalid = axi_rvalid;

// awready and awaddr
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_awready <= 1'b0;
      axi_awaddr <= 0;
      aw_en <= 1'b1;
    end 
  else
    begin    
      if (~axi_awready && axi_ctrl.awvalid && axi_ctrl.wvalid && aw_en)
        begin
          axi_awready <= 1'b1;
          aw_en <= 1'b0;
          axi_awaddr <= axi_ctrl.awaddr;
        end
      else if (axi_ctrl.bready && axi_bvalid)
        begin
          aw_en <= 1'b1;
          axi_awready <= 1'b0;
        end
      else           
        begin
          axi_awready <= 1'b0;
        end
    end 
end  

// arready and araddr
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_arready <= 1'b0;
      axi_araddr  <= 0;
    end 
  else
    begin    
      if (~axi_arready && axi_ctrl.arvalid)
        begin
          axi_arready <= 1'b1;
          axi_araddr  <= axi_ctrl.araddr;
        end
      else
        begin
          axi_arready <= 1'b0;
        end
    end 
end    

// bvalid and bresp
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_bvalid  <= 0;
      axi_bresp   <= 2'b0;
    end 
  else
    begin    
      if (axi_awready && axi_ctrl.awvalid && ~axi_bvalid && axi_wready && axi_ctrl.wvalid)
        begin
          axi_bvalid <= 1'b1;
          axi_bresp  <= 2'b0;
        end                   
      else
        begin
          if (axi_ctrl.bready && axi_bvalid) 
            begin
              axi_bvalid <= 1'b0; 
            end  
        end
    end
end

// wready
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_wready <= 1'b0;
    end 
  else
    begin    
      if (~axi_wready && axi_ctrl.wvalid && axi_ctrl.awvalid && aw_en )
        begin
          axi_wready <= 1'b1;
        end
      else
        begin
          axi_wready <= 1'b0;
        end
    end 
end  

// rvalid and rresp (1Del?)
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_rvalid <= 0;
      axi_rresp  <= 0;
    end 
  else
    begin    
      if (axi_arready && axi_ctrl.arvalid && ~axi_rvalid)
        begin
          axi_rvalid <= 1'b1;
          axi_rresp  <= 2'b0;
        end   
      else if (axi_rvalid && axi_ctrl.rready)
        begin
          axi_rvalid <= 1'b0;
        end                
    end
end    

// ILA Core for debugging ctrl_slv signals
// ila_ctrl_slv ila_ctrl_slv_inst (
//     .clk(aclk),
    
//     .probe0(slv_reg_wren),           // 1 bit
//     .probe1(reg_sel),                // 3 bits  
//     .probe2(unit_sel),               // 1 bit
//     .probe3(rd_ptr[0]),              // 5 bits
//     .probe4(wr_ptr[0]),              // 5 bits
//     .probe5(cfg_valid_out[0]),       // 1 bit
//     .probe6(cfg_ready_from_stage[0]), // 1 bit
//     .probe7(cfg_data_out[0]),        // 48 bits
//     .probe8(perf_rst[0]),            // 1 bit
//     .probe9(hard_rst_n[0]),          // 1 bit
//     // AXI AW channel signals
//     .probe10(axi_ctrl.awaddr),       // AXI_ADDR_BITS bits
//     .probe11(axi_ctrl.awvalid),      // 1 bit
//     .probe12(axi_ctrl.awready),      // 1 bit
//     // AXI W channel signals  
//     .probe13(axi_ctrl.wdata),        // AXIL_DATA_BITS bits
//     .probe14(axi_ctrl.wstrb),        // AXIL_DATA_BITS/8 bits
//     .probe15(axi_ctrl.wvalid),       // 1 bit
//     .probe16(axi_ctrl.wready)        // 1 bit
// );

endmodule // perf_fpga slave