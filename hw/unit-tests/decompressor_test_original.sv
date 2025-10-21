/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
// always_comb sq_rd.tie_off_m();
// always_comb sq_wr.tie_off_m();
// always_comb cq_rd.tie_off_s();
// always_comb cq_wr.tie_off_s();

// always_comb axis_host_recv[1].tie_off_s();
// always_comb axis_host_recv[2].tie_off_s();
// always_comb axis_host_recv[3].tie_off_s();
// always_comb axis_host_recv[4].tie_off_s();
// always_comb axis_host_recv[5].tie_off_s();
// always_comb axis_host_send[1].tie_off_m();
// always_comb axis_host_send[2].tie_off_m();
// always_comb axis_host_send[3].tie_off_m();
// always_comb axis_host_send[4].tie_off_m();
// always_comb axis_host_send[5].tie_off_m();

/* -- USER LOGIC -------------------------------------------------------- */

/* -- INPUT ------------------------------------------------------------- */

AXI4SC #(.AXI4S_DATA_BITS(512)) host_in (.aclk(aclk));
assign axis_host_recv[0].tready = host_in.tready;
assign host_in.tdata = axis_host_recv[0].tdata;
assign host_in.tkeep = axis_host_recv[0].tkeep;
assign host_in.tlast = axis_host_recv[0].tlast;
assign host_in.tvalid = axis_host_recv[0].tvalid;

// values for compression:
// 3'd0 => bypass
// 3'd1 => snappy
// 3'd2 => simulation
logic [CONFIG_WIDTH-1:0] tconfig;  // Fix array syntax
assign tconfig = '0;
// assign tconfig[COMPRESSION_CONFIG_INDEX+2:COMPRESSION_CONFIG_INDEX] = 3'd1;
assign host_in.tconfig = tconfig;

/* -- OUTPUT ------------------------------------------------------------ */

integer output_databeat;
AXI4SC #(.AXI4S_DATA_BITS(512)) host_out (.aclk(aclk));
assign host_out.tready = axis_host_send[0].tready;
assign axis_host_send[0].tdata = host_out.tdata;
assign axis_host_send[0].tkeep = host_out.tkeep;
assign axis_host_send[0].tlast = host_out.tlast;
assign axis_host_send[0].tvalid = host_out.tvalid;
assign axis_host_send[0].tid = output_databeat;


/* -- DESIGN WIRING ----------------------------------------------------- */

// logic read_one;
always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin 
        output_databeat  <= 0;
        tconfig[COMPRESSION_CONFIG_INDEX+2:COMPRESSION_CONFIG_INDEX] <= 3'd1;
        // read_one <= 1'b0;
    end else begin
        if (host_out.tvalid && host_out.tready) begin
          $display("! got databeat out(valid: %x, ready: %x, last: %x)", host_out.tvalid, host_out.tready, host_out.tlast);
          output_databeat <= output_databeat + 1;

          if (host_out.tlast) begin
            $display("!! got tlast after %d databeats", output_databeat);
            output_databeat <= 0;

            // if (read_one == 1'b1) begin
            //     // only move to a raw stream on the third input transfer
            //     $display("!!!! setting to RAW for next transfer");
            //     assign tconfig[COMPRESSION_CONFIG_INDEX+2:COMPRESSION_CONFIG_INDEX] = 3'd0;
            // end
            //
            // read_one <= 1'b1;
          end
        end
    end
end

decompressor decompressor_inst (
  .clk(aclk),
  .rst_n(aresetn),

  .in_stream(host_in),
  .out_stream(host_out)
);
