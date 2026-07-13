# Select the correct ILA IP for the target architecture.
# NOTE: On Versal (e.g. V80) the IP is called axis_ila instead of ila,
#       and the versioned -version flag of the UltraScale+ ila core does not apply.
if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    set ila_create_args [list -name ila -vendor xilinx.com -library ip -version 6.2]
} elseif {$cfg(fpga_arch) eq "versal"} {
    set ila_create_args [list -name axis_ila -vendor xilinx.com -library ip]
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}

create_ip {*}$ila_create_args -module_name ila_run_decoder
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {40} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {3} \
    CONFIG.C_PROBE10_WIDTH {7} \
    CONFIG.C_PROBE11_WIDTH {7} \
    CONFIG.C_PROBE12_WIDTH {1} \
    CONFIG.C_PROBE13_WIDTH {32} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {28} \
    CONFIG.C_PROBE16_WIDTH {32} \
    CONFIG.C_PROBE17_WIDTH {32} \
    CONFIG.C_PROBE18_WIDTH {17} \
    CONFIG.C_PROBE19_WIDTH {4} \
    CONFIG.C_PROBE20_WIDTH {32} \
    CONFIG.C_PROBE21_WIDTH {1} \
    CONFIG.C_PROBE22_WIDTH {1} \
    CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {1} \
    CONFIG.C_PROBE25_WIDTH {1} \
    CONFIG.C_PROBE26_WIDTH {1} \
    CONFIG.C_PROBE27_WIDTH {1} \
    CONFIG.C_PROBE28_WIDTH {1} \
    CONFIG.C_PROBE29_WIDTH {1} \
    CONFIG.C_PROBE30_WIDTH {1} \
    CONFIG.C_PROBE31_WIDTH {1} \
    CONFIG.C_PROBE32_WIDTH {1} \
    CONFIG.C_PROBE33_WIDTH {1} \
    CONFIG.C_PROBE34_WIDTH {1} \
    CONFIG.C_PROBE35_WIDTH {1} \
    CONFIG.C_PROBE36_WIDTH {1} \
    CONFIG.C_PROBE37_WIDTH {1} \
    CONFIG.C_PROBE38_WIDTH {1} \
    CONFIG.C_PROBE39_WIDTH {32} \
] [get_ips ila_run_decoder]

create_ip {*}$ila_create_args -module_name ila_page_decoder
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {30} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {2} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {2} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {64} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {64} \
    CONFIG.C_PROBE20_WIDTH {1} \
    CONFIG.C_PROBE21_WIDTH {1} \
    CONFIG.C_PROBE22_WIDTH {1} \
    CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {64} \
    CONFIG.C_PROBE25_WIDTH {1} \
    CONFIG.C_PROBE26_WIDTH {1} \
    CONFIG.C_PROBE27_WIDTH {1} \
    CONFIG.C_PROBE28_WIDTH {64} \
    CONFIG.C_PROBE29_WIDTH {1} \
] [get_ips ila_page_decoder]

create_ip {*}$ila_create_args -module_name ila_hybrid_page_decoder
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {10} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {2} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {64} \
] [get_ips ila_hybrid_page_decoder]

create_ip {*}$ila_create_args -module_name ila_decompressor
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {18} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} \
    CONFIG.C_PROBE13_WIDTH {64} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {64} \
] [get_ips ila_decompressor]

create_ip {*}$ila_create_args -module_name ila_top
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {9} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {64} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {64} \
] [get_ips ila_top]

# ---------------------------------------------------------------------------
# Hang-debug ILAs for the merged two-stream ColumnChunkDecoder design.
# All instantiations are guarded by `ifdef SYNTHESIS, so simulation is
# unaffected. C_INPUT_PIPE_STAGES 2 decouples the probes from the 250 MHz
# datapath timing; C_EN_STRG_QUAL 1 allows capturing only cycles of interest
# (e.g. handshake activity) so a deep window survives long stalls.
# ---------------------------------------------------------------------------

# Per-channel dataflow boundary: config, input, decoder outputs, writer inputs.
create_ip {*}$ila_create_args -module_name ila_cc_top
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {21} \
    CONFIG.C_DATA_DEPTH {8192} \
    CONFIG.C_INPUT_PIPE_STAGES {2} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {1} \
] [get_ips ila_cc_top]

# Shell-facing write/notify interface: sq_wr requests with address/length,
# cq_wr ack identity fields, notify handshakes with pid + value.
create_ip {*}$ila_create_args -module_name ila_shell_io
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {19} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_INPUT_PIPE_STAGES {2} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {28} \
    CONFIG.C_PROBE4_WIDTH {48} \
    CONFIG.C_PROBE5_WIDTH {4} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {6} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {5} \
    CONFIG.C_PROBE11_WIDTH {2} \
    CONFIG.C_PROBE12_WIDTH {4} \
    CONFIG.C_PROBE13_WIDTH {6} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {6} \
    CONFIG.C_PROBE18_WIDTH {32} \
] [get_ips ila_shell_io]

# ColumnChunkDecoder internals: page FSM, per-path handshakes, selector and
# config holds, heap normalizer/dummy-beat machinery.
create_ip {*}$ila_create_args -module_name ila_column_chunk_decoder
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {45} \
    CONFIG.C_DATA_DEPTH {2048} \
    CONFIG.C_INPUT_PIPE_STAGES {2} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {2} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {3} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {2} \
    CONFIG.C_PROBE10_WIDTH {32} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {3} \
    CONFIG.C_PROBE13_WIDTH {3} \
    CONFIG.C_PROBE14_WIDTH {3} \
    CONFIG.C_PROBE15_WIDTH {3} \
    CONFIG.C_PROBE16_WIDTH {3} \
    CONFIG.C_PROBE17_WIDTH {3} \
    CONFIG.C_PROBE18_WIDTH {3} \
    CONFIG.C_PROBE19_WIDTH {3} \
    CONFIG.C_PROBE20_WIDTH {3} \
    CONFIG.C_PROBE21_WIDTH {3} \
    CONFIG.C_PROBE22_WIDTH {3} \
    CONFIG.C_PROBE23_WIDTH {3} \
    CONFIG.C_PROBE24_WIDTH {3} \
    CONFIG.C_PROBE25_WIDTH {3} \
    CONFIG.C_PROBE26_WIDTH {3} \
    CONFIG.C_PROBE27_WIDTH {3} \
    CONFIG.C_PROBE28_WIDTH {3} \
    CONFIG.C_PROBE29_WIDTH {3} \
    CONFIG.C_PROBE30_WIDTH {3} \
    CONFIG.C_PROBE31_WIDTH {3} \
    CONFIG.C_PROBE32_WIDTH {3} \
    CONFIG.C_PROBE33_WIDTH {3} \
    CONFIG.C_PROBE34_WIDTH {9} \
    CONFIG.C_PROBE35_WIDTH {7} \
    CONFIG.C_PROBE36_WIDTH {1} \
    CONFIG.C_PROBE37_WIDTH {1} \
    CONFIG.C_PROBE38_WIDTH {1} \
    CONFIG.C_PROBE39_WIDTH {1} \
    CONFIG.C_PROBE40_WIDTH {16} \
    CONFIG.C_PROBE41_WIDTH {16} \
    CONFIG.C_PROBE42_WIDTH {32} \
    CONFIG.C_PROBE43_WIDTH {1} \
    CONFIG.C_PROBE44_WIDTH {2} \
] [get_ips ila_column_chunk_decoder]

# PairedOutputWriter: both StreamWriters' request/data/ack/notify/buffer
# handshakes plus the merged channel-level traffic.
create_ip {*}$ila_create_args -module_name ila_paired_writer
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_INPUT_PIPE_STAGES {2} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {2} \
    CONFIG.C_PROBE2_WIDTH {2} \
    CONFIG.C_PROBE3_WIDTH {3} \
    CONFIG.C_PROBE4_WIDTH {3} \
    CONFIG.C_PROBE5_WIDTH {2} \
    CONFIG.C_PROBE6_WIDTH {2} \
    CONFIG.C_PROBE7_WIDTH {2} \
    CONFIG.C_PROBE8_WIDTH {2} \
    CONFIG.C_PROBE9_WIDTH {3} \
    CONFIG.C_PROBE10_WIDTH {3} \
    CONFIG.C_PROBE11_WIDTH {2} \
    CONFIG.C_PROBE12_WIDTH {28} \
    CONFIG.C_PROBE13_WIDTH {32} \
    CONFIG.C_PROBE14_WIDTH {2} \
    CONFIG.C_PROBE15_WIDTH {3} \
] [get_ips ila_paired_writer]

# StreamWriterPairArbiter: grant machinery, order-FIFO heads, completion
# routing. This is where a lost/misrouted ack or a stuck grant shows up.
create_ip {*}$ila_create_args -module_name ila_pair_arbiter
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {13} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_INPUT_PIPE_STAGES {2} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {2} \
    CONFIG.C_PROBE2_WIDTH {3} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {2} \
    CONFIG.C_PROBE6_WIDTH {2} \
    CONFIG.C_PROBE7_WIDTH {2} \
    CONFIG.C_PROBE8_WIDTH {2} \
    CONFIG.C_PROBE9_WIDTH {2} \
    CONFIG.C_PROBE10_WIDTH {2} \
    CONFIG.C_PROBE11_WIDTH {2} \
    CONFIG.C_PROBE12_WIDTH {3} \
] [get_ips ila_pair_arbiter]
