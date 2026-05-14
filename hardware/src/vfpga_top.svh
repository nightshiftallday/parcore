`include "lynx_macros.svh"
`include "libstf_macros.svh"

import parcore::*;
import libstf::*;

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb sq_rd.tie_off_m();
always_comb cq_rd.tie_off_s();

localparam N_STREAMS = N_STRM_AXI;
localparam DATABEAT_SIZE = 64;

/* -- Fix clock and reset names ----------------------------------------- */
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

/* -- CONFIG ------------------------------------------------------------ */
write_config_i write_configs[4](.*);
read_config_i  read_configs [4](.*);
GlobalConfig #(
    .SYSTEM_ID(PARCORE_SYSTEM_ID),
    .NUM_CONFIGS(4),
    .ADDR_SPACE_SIZES({N_STREAMS+1, COLUMN_CHUNK_DECODER_CONFIG_REGS*N_STREAMS, PAGE_DECODER_CONFIG_REGS*N_STREAMS, 8*N_STREAMS+1})
) inst_config (
    .clk(clk),
    .rst_n(rst_n),

    .axi_ctrl(axi_ctrl),

    .write_configs(write_configs),
    .read_configs(read_configs)
);

mem_config_i mem_conf[N_STREAMS](.*);
MemConfig #(
    .NUM_STREAMS(N_STREAMS)
) inst_mem_config (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(write_configs[0]),
    .read_config(read_configs[0]),

    .out(mem_conf)
);

column_chunk_decoder_config_i column_chunk_conf[N_STREAMS](.*);
ColumnChunkDecoderConfig #(
    .NUM_DECODERS(N_STREAMS)
) inst_column_chunk_decoder_config (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(write_configs[1]),
    .read_config(read_configs[1]),

    .out(column_chunk_conf)
);

page_decoder_config_i page_conf[N_STREAMS](.*);
PageDecoderConfig #(
    .NUM_DECODERS(N_STREAMS)
) inst_page_decoder_config (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(write_configs[2]),
    .read_config(read_configs[2]),

    .out(page_conf)
);

// -- Profiling ------------------------------------------------------------------------------------

// We use this for profiling in the output buffer manager software example
data64_t perf_counters[8 * N_STREAMS];
data64_t write_regs[1];
GenericConfig #(
    .NUM_READ_REGISTERS(8 * N_STRM_AXI),
    .NUM_WRITE_REGISTERS(1)
) inst_generic_config (
    .clk(clk),
    .rst_n(rst_n),

    .write_config(write_configs[3]),
    .read_config(read_configs[3]),

    .in(perf_counters),
    .out(write_regs)
);

data64_t num_inputs;
assign num_inputs = write_regs[0];

AXI4S outputs [N_STREAMS](.aclk(clk), .aresetn(rst_n));

generate
    for (genvar I = 0; I < N_STREAMS; I++) begin : gen
        /* -- INPUT ------------------------------------------------------------- */

        AXI4S axi_host_recv (.aclk(clk), .aresetn(rst_n));
        `AXIS_ASSIGN(axis_host_recv[I], axi_host_recv)

        ndata_i #(data8_t, DATABEAT_SIZE) in(clk, rst_n);
        AXIToNData #(data8_t, DATABEAT_SIZE) inst_axi_to_ndata (
            .clk(clk),
            .rst_n(rst_n),

            .in(axi_host_recv),
            .out(in)
        );

        /* -- OUTPUT ------------------------------------------------------------ */

        ndata_i #(data8_t, DATABEAT_SIZE) out_u8(clk, rst_n);
        NDataToAXI #(data8_t, DATABEAT_SIZE) inst_ndata_to_axi (
            .clk(clk),
            .rst_n(rst_n),

            .in(out_u8),
            .out(outputs[I])
        );

        // discard typed interface
        typed_ndata_i #(DATABEAT_SIZE) out(clk, rst_n);
        `DATA_ASSIGN(out, out_u8);

        /* -- DESIGN WIRING ----------------------------------------------------- */

        ColumnChunkDecoder #(
            .DATABEAT_SIZE(DATABEAT_SIZE)
        ) inst_column_chunk_decoder (
            .clk(clk),
            .rst_n(rst_n),

            .column_chunk_conf(column_chunk_conf[I]),
            .page_conf(page_conf[I]),

            .in(in),
            .out(out)
        );

        /* -- PROFILING --------------------------------------------------------- */
        /*
        data64_t inputs_counter, n_inputs_counter;
        logic    is_stop;

        always_ff @(posedge clk) begin
            if (!rst_n) begin
                inputs_counter <= '0;
            end else begin
                inputs_counter <= n_inputs_counter;
            end
        end

        always_comb begin
            n_inputs_counter = inputs_counter;
            is_stop = 1'b0;

            if (in.valid && in.last && in.ready) begin
                if (inputs_counter == num_inputs - 1) begin
                    n_inputs_counter = '0;
                    is_stop = 1'b1;
                end else begin
                    n_inputs_counter = inputs_counter + 1;
                end
            end
        end

        StreamProfiler inst_perf_counter_in (
            .clk(clk),
            .rst_n(rst_n),

            .last (in.last),
            .valid(in.valid),
            .ready(in.ready),

            .stop(is_stop_in),

            .handshakes_cycles(perf_counters[8 * I + 0]),
            .starved_cycles   (perf_counters[8 * I + 1]),
            .stalled_cycles   (perf_counters[8 * I + 2]),
            .idle_cycles      (perf_counters[8 * I + 3])
        );

        StreamProfiler inst_perf_counter_out (
            .clk(clk),
            .rst_n(rst_n),

            .last (out.last),
            .valid(out.valid),
            .ready(out.ready),

            .stop(out.valid && out.last && out.ready),

            .handshakes_cycles(perf_counters[8 * I + 4]),
            .starved_cycles   (perf_counters[8 * I + 5]),
            .stalled_cycles   (perf_counters[8 * I + 6]),
            .idle_cycles      (perf_counters[8 * I + 7])
        );
        */

        /*
        ila_top inst_ila_top (
            .clk(clk),
            .probe0(rst_n),

            .probe1(axi_host_recv.tready),
            .probe2(axi_host_recv.tvalid),
            .probe3(axi_host_recv.tlast),
            .probe4(axi_host_recv.tkeep),

            .probe5(in.ready),
            .probe6(in.valid),
            .probe7(in.last),
            .probe8(in.keep)
        );
        */
    end
endgenerate

OutputWriter inst_output_writer (
    .clk(clk),
    .rst_n(rst_n),

    .sq_wr(sq_wr),
    .cq_wr(cq_wr),
    .notify(notify),

    .mem_config(mem_conf),

    .data_in(outputs),
    .data_out(axis_host_send)
);
