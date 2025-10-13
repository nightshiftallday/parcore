# ==================== ILA IP Core Definitions ====================

# Top-level ILA - monitors overall I/O streams and performance metrics
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_top
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {512} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {512} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {64} \
    CONFIG.C_PROBE9_WIDTH {64} \
    CONFIG.C_PROBE10_WIDTH {64} \
    CONFIG.C_PROBE11_WIDTH {64} \
    CONFIG.C_PROBE12_WIDTH {64} \
    CONFIG.C_PROBE13_WIDTH {5} \
    CONFIG.C_PROBE14_WIDTH {9} \
    CONFIG.C_PROBE15_WIDTH {48} \
    CONFIG.C_PROBE0_MU_CNT {4} \
    CONFIG.C_PROBE1_MU_CNT {4} \
    CONFIG.C_PROBE2_MU_CNT {4} \
    CONFIG.C_PROBE3_MU_CNT {4} \
    CONFIG.C_PROBE4_MU_CNT {4} \
    CONFIG.C_PROBE5_MU_CNT {4} \
    CONFIG.C_PROBE6_MU_CNT {4} \
    CONFIG.C_PROBE7_MU_CNT {4} \
    CONFIG.C_PROBE8_MU_CNT {4} \
    CONFIG.C_PROBE9_MU_CNT {4} \
    CONFIG.C_PROBE10_MU_CNT {4} \
    CONFIG.C_PROBE11_MU_CNT {4} \
    CONFIG.C_PROBE12_MU_CNT {4} \
    CONFIG.C_PROBE13_MU_CNT {4} \
    CONFIG.C_PROBE14_MU_CNT {4} \
    CONFIG.C_PROBE15_MU_CNT {4} \
] [get_ips ila_top]

# Stage Reader ILA - monitors stage_reader module (renamed from ila_stage)
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_stage_reader
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {14} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {512} \
    CONFIG.C_PROBE1_WIDTH {64} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {48} \
    CONFIG.C_PROBE6_WIDTH {512} \
    CONFIG.C_PROBE7_WIDTH {64} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {5} \
    CONFIG.C_PROBE12_WIDTH {4} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE0_MU_CNT {2} \
    CONFIG.C_PROBE1_MU_CNT {2} \
    CONFIG.C_PROBE2_MU_CNT {2} \
    CONFIG.C_PROBE3_MU_CNT {2} \
    CONFIG.C_PROBE4_MU_CNT {2} \
    CONFIG.C_PROBE5_MU_CNT {2} \
    CONFIG.C_PROBE6_MU_CNT {2} \
    CONFIG.C_PROBE7_MU_CNT {2} \
    CONFIG.C_PROBE8_MU_CNT {2} \
    CONFIG.C_PROBE9_MU_CNT {2} \
    CONFIG.C_PROBE10_MU_CNT {2} \
    CONFIG.C_PROBE11_MU_CNT {2} \
    CONFIG.C_PROBE12_MU_CNT {2} \
    CONFIG.C_PROBE13_MU_CNT {2} \
] [get_ips ila_stage_reader]

# Stage ILA - optimized for pipeline stage monitoring (stage1 - currently commented out)
# create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_stage
# set_property -dict [list \
#     CONFIG.C_NUM_OF_PROBES {13} \
#     CONFIG.C_EN_STRG_QUAL {1} \
#     CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
#     CONFIG.C_DATA_DEPTH {1024} \
#     CONFIG.C_PROBE0_WIDTH {512} \
#     CONFIG.C_PROBE1_WIDTH {1} \
#     CONFIG.C_PROBE2_WIDTH {1} \
#     CONFIG.C_PROBE3_WIDTH {1} \
#     CONFIG.C_PROBE4_WIDTH {48} \
#     CONFIG.C_PROBE5_WIDTH {512} \
#     CONFIG.C_PROBE6_WIDTH {1} \
#     CONFIG.C_PROBE7_WIDTH {1} \
#     CONFIG.C_PROBE8_WIDTH {1} \
#     CONFIG.C_PROBE9_WIDTH {48} \
#     CONFIG.C_PROBE10_WIDTH {5} \
#     CONFIG.C_PROBE11_WIDTH {4} \
#     CONFIG.C_PROBE12_WIDTH {1} \
#     CONFIG.C_PROBE0_MU_CNT {2} \
#     CONFIG.C_PROBE1_MU_CNT {2} \
#     CONFIG.C_PROBE2_MU_CNT {2} \
#     CONFIG.C_PROBE3_MU_CNT {2} \
#     CONFIG.C_PROBE4_MU_CNT {2} \
#     CONFIG.C_PROBE5_MU_CNT {2} \
#     CONFIG.C_PROBE6_MU_CNT {2} \
#     CONFIG.C_PROBE7_MU_CNT {2} \
#     CONFIG.C_PROBE8_MU_CNT {2} \
#     CONFIG.C_PROBE9_MU_CNT {2} \
#     CONFIG.C_PROBE10_MU_CNT {2} \
#     CONFIG.C_PROBE11_MU_CNT {2} \
#     CONFIG.C_PROBE12_MU_CNT {2} \
# ] [get_ips ila_stage]

# # Reader ILA - compact version for individual reader submodules
# create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_reader
# set_property -dict [list \
#     CONFIG.C_NUM_OF_PROBES {11} \
#     CONFIG.C_EN_STRG_QUAL {1} \
#     CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
#     CONFIG.C_DATA_DEPTH {1024} \
#     CONFIG.C_PROBE0_WIDTH {512} \
#     CONFIG.C_PROBE1_WIDTH {1} \
#     CONFIG.C_PROBE2_WIDTH {1} \
#     CONFIG.C_PROBE3_WIDTH {1} \
#     CONFIG.C_PROBE4_WIDTH {512} \
#     CONFIG.C_PROBE5_WIDTH {1} \
#     CONFIG.C_PROBE6_WIDTH {1} \
#     CONFIG.C_PROBE7_WIDTH {1} \
#     CONFIG.C_PROBE8_WIDTH {8} \
#     CONFIG.C_PROBE9_WIDTH {48} \
#     CONFIG.C_PROBE10_WIDTH {48} \
#     CONFIG.C_PROBE0_MU_CNT {2} \
#     CONFIG.C_PROBE1_MU_CNT {2} \
#     CONFIG.C_PROBE2_MU_CNT {2} \
#     CONFIG.C_PROBE3_MU_CNT {2} \
#     CONFIG.C_PROBE4_MU_CNT {2} \
#     CONFIG.C_PROBE5_MU_CNT {2} \
#     CONFIG.C_PROBE6_MU_CNT {2} \
#     CONFIG.C_PROBE7_MU_CNT {2} \
#     CONFIG.C_PROBE8_MU_CNT {2} \
#     CONFIG.C_PROBE9_MU_CNT {2} \
#     CONFIG.C_PROBE10_MU_CNT {2} \
# ] [get_ips ila_reader]

# Alligner ILA - monitors config_alligner module behavior
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_alligner
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {512} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {512} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {48} \
    CONFIG.C_PROBE9_WIDTH {3} \
    CONFIG.C_PROBE10_WIDTH {2} \
    CONFIG.C_PROBE11_WIDTH {48} \
    CONFIG.C_PROBE12_WIDTH {38} \
    CONFIG.C_PROBE13_WIDTH {4} \
    CONFIG.C_PROBE14_WIDTH {4} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE0_MU_CNT {2} \
    CONFIG.C_PROBE1_MU_CNT {2} \
    CONFIG.C_PROBE2_MU_CNT {2} \
    CONFIG.C_PROBE3_MU_CNT {2} \
    CONFIG.C_PROBE4_MU_CNT {2} \
    CONFIG.C_PROBE5_MU_CNT {2} \
    CONFIG.C_PROBE6_MU_CNT {2} \
    CONFIG.C_PROBE7_MU_CNT {2} \
    CONFIG.C_PROBE8_MU_CNT {2} \
    CONFIG.C_PROBE9_MU_CNT {2} \
    CONFIG.C_PROBE10_MU_CNT {2} \
    CONFIG.C_PROBE11_MU_CNT {2} \
    CONFIG.C_PROBE12_MU_CNT {2} \
    CONFIG.C_PROBE13_MU_CNT {2} \
    CONFIG.C_PROBE14_MU_CNT {2} \
    CONFIG.C_PROBE15_MU_CNT {2} \
] [get_ips ila_alligner]

# # Control Slave ILA - monitors ctrl_slv module signals for debugging
# create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_ctrl_slv
# set_property -dict [list \
#     CONFIG.C_NUM_OF_PROBES {17} \
#     CONFIG.C_EN_STRG_QUAL {1} \
#     CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
#     CONFIG.C_DATA_DEPTH {1024} \
#     CONFIG.C_PROBE0_WIDTH {1} \
#     CONFIG.C_PROBE1_WIDTH {3} \
#     CONFIG.C_PROBE2_WIDTH {1} \
#     CONFIG.C_PROBE3_WIDTH {5} \
#     CONFIG.C_PROBE4_WIDTH {5} \
#     CONFIG.C_PROBE5_WIDTH {1} \
#     CONFIG.C_PROBE6_WIDTH {1} \
#     CONFIG.C_PROBE7_WIDTH {48} \
#     CONFIG.C_PROBE8_WIDTH {1} \
#     CONFIG.C_PROBE9_WIDTH {1} \
#     CONFIG.C_PROBE10_WIDTH {7} \
#     CONFIG.C_PROBE11_WIDTH {1} \
#     CONFIG.C_PROBE12_WIDTH {1} \
#     CONFIG.C_PROBE13_WIDTH {64} \
#     CONFIG.C_PROBE14_WIDTH {8} \
#     CONFIG.C_PROBE15_WIDTH {1} \
#     CONFIG.C_PROBE16_WIDTH {1} \
#     CONFIG.C_PROBE0_MU_CNT {2} \
#     CONFIG.C_PROBE1_MU_CNT {2} \
#     CONFIG.C_PROBE2_MU_CNT {2} \
#     CONFIG.C_PROBE3_MU_CNT {2} \
#     CONFIG.C_PROBE4_MU_CNT {2} \
#     CONFIG.C_PROBE5_MU_CNT {2} \
#     CONFIG.C_PROBE6_MU_CNT {2} \
#     CONFIG.C_PROBE7_MU_CNT {2} \
#     CONFIG.C_PROBE8_MU_CNT {2} \
#     CONFIG.C_PROBE9_MU_CNT {2} \
#     CONFIG.C_PROBE10_MU_CNT {2} \
#     CONFIG.C_PROBE11_MU_CNT {2} \
#     CONFIG.C_PROBE12_MU_CNT {2} \
#     CONFIG.C_PROBE13_MU_CNT {2} \
#     CONFIG.C_PROBE14_MU_CNT {2} \
#     CONFIG.C_PROBE15_MU_CNT {2} \
#     CONFIG.C_PROBE16_MU_CNT {2} \
# ] [get_ips ila_ctrl_slv]

# VHSNUnzip Wrapper ILA - monitors decompression wrapper signals
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_vhsnunzip_wrapper
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {28} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {512} \
    CONFIG.C_PROBE1_WIDTH {64} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {512} \
    CONFIG.C_PROBE6_WIDTH {64} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {64} \
    CONFIG.C_PROBE13_WIDTH {3} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {64} \
    CONFIG.C_PROBE19_WIDTH {4} \
    CONFIG.C_PROBE20_WIDTH {1} \
    CONFIG.C_PROBE21_WIDTH {3} \
    CONFIG.C_PROBE22_WIDTH {3} \
    CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {6} \
    CONFIG.C_PROBE25_WIDTH {512} \
    CONFIG.C_PROBE26_WIDTH {64} \
    CONFIG.C_PROBE27_WIDTH {1} \
    CONFIG.C_PROBE0_MU_CNT {2} \
    CONFIG.C_PROBE1_MU_CNT {2} \
    CONFIG.C_PROBE2_MU_CNT {2} \
    CONFIG.C_PROBE3_MU_CNT {2} \
    CONFIG.C_PROBE4_MU_CNT {2} \
    CONFIG.C_PROBE5_MU_CNT {2} \
    CONFIG.C_PROBE6_MU_CNT {2} \
    CONFIG.C_PROBE7_MU_CNT {2} \
    CONFIG.C_PROBE8_MU_CNT {2} \
    CONFIG.C_PROBE9_MU_CNT {2} \
    CONFIG.C_PROBE10_MU_CNT {2} \
    CONFIG.C_PROBE11_MU_CNT {2} \
    CONFIG.C_PROBE12_MU_CNT {2} \
    CONFIG.C_PROBE13_MU_CNT {2} \
    CONFIG.C_PROBE14_MU_CNT {2} \
    CONFIG.C_PROBE15_MU_CNT {2} \
    CONFIG.C_PROBE16_MU_CNT {2} \
    CONFIG.C_PROBE17_MU_CNT {2} \
    CONFIG.C_PROBE18_MU_CNT {2} \
    CONFIG.C_PROBE19_MU_CNT {2} \
    CONFIG.C_PROBE20_MU_CNT {2} \
    CONFIG.C_PROBE21_MU_CNT {2} \
    CONFIG.C_PROBE22_MU_CNT {2} \
    CONFIG.C_PROBE23_MU_CNT {2} \
    CONFIG.C_PROBE24_MU_CNT {2} \
    CONFIG.C_PROBE25_MU_CNT {2} \
    CONFIG.C_PROBE26_MU_CNT {2} \
    CONFIG.C_PROBE27_MU_CNT {2} \
] [get_ips ila_vhsnunzip_wrapper]

# Reader ILA - compact version for individual reader submodules (currently commented out)
# create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_reader
# set_property -dict [list \
#     CONFIG.C_NUM_OF_PROBES {11} \
#     CONFIG.C_EN_STRG_QUAL {1} \
#     CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
#     CONFIG.C_DATA_DEPTH {1024} \
#     CONFIG.C_PROBE0_WIDTH {512} \
#     CONFIG.C_PROBE1_WIDTH {1} \
#     CONFIG.C_PROBE2_WIDTH {1} \
#     CONFIG.C_PROBE3_WIDTH {1} \
#     CONFIG.C_PROBE4_WIDTH {512} \
#     CONFIG.C_PROBE5_WIDTH {1} \
#     CONFIG.C_PROBE6_WIDTH {1} \
#     CONFIG.C_PROBE7_WIDTH {1} \
#     CONFIG.C_PROBE8_WIDTH {8} \
#     CONFIG.C_PROBE9_WIDTH {48} \
#     CONFIG.C_PROBE10_WIDTH {48} \
#     CONFIG.C_PROBE0_MU_CNT {2} \
#     CONFIG.C_PROBE1_MU_CNT {2} \
#     CONFIG.C_PROBE2_MU_CNT {2} \
#     CONFIG.C_PROBE3_MU_CNT {2} \
#     CONFIG.C_PROBE4_MU_CNT {2} \
#     CONFIG.C_PROBE5_MU_CNT {2} \
#     CONFIG.C_PROBE6_MU_CNT {2} \
#     CONFIG.C_PROBE7_MU_CNT {2} \
#     CONFIG.C_PROBE8_MU_CNT {2} \
#     CONFIG.C_PROBE9_MU_CNT {2} \
#     CONFIG.C_PROBE10_MU_CNT {2} \
# ] [get_ips ila_reader]

# Control Slave ILA - monitors ctrl_slv module signals for debugging (currently commented out)
# create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_ctrl_slv
# set_property -dict [list \
#     CONFIG.C_NUM_OF_PROBES {17} \
#     CONFIG.C_EN_STRG_QUAL {1} \
#     CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
#     CONFIG.C_DATA_DEPTH {1024} \
#     CONFIG.C_PROBE0_WIDTH {1} \
#     CONFIG.C_PROBE1_WIDTH {3} \
#     CONFIG.C_PROBE2_WIDTH {1} \
#     CONFIG.C_PROBE3_WIDTH {5} \
#     CONFIG.C_PROBE4_WIDTH {5} \
#     CONFIG.C_PROBE5_WIDTH {1} \
#     CONFIG.C_PROBE6_WIDTH {1} \
#     CONFIG.C_PROBE7_WIDTH {48} \
#     CONFIG.C_PROBE8_WIDTH {1} \
#     CONFIG.C_PROBE9_WIDTH {1} \
#     CONFIG.C_PROBE10_WIDTH {7} \
#     CONFIG.C_PROBE11_WIDTH {1} \
#     CONFIG.C_PROBE12_WIDTH {1} \
#     CONFIG.C_PROBE13_WIDTH {64} \
#     CONFIG.C_PROBE14_WIDTH {8} \
#     CONFIG.C_PROBE15_WIDTH {1} \
#     CONFIG.C_PROBE16_WIDTH {1} \
#     CONFIG.C_PROBE0_MU_CNT {2} \
#     CONFIG.C_PROBE1_MU_CNT {2} \
#     CONFIG.C_PROBE2_MU_CNT {2} \
#     CONFIG.C_PROBE3_MU_CNT {2} \
#     CONFIG.C_PROBE4_MU_CNT {2} \
#     CONFIG.C_PROBE5_MU_CNT {2} \
#     CONFIG.C_PROBE6_MU_CNT {2} \
#     CONFIG.C_PROBE7_MU_CNT {2} \
#     CONFIG.C_PROBE8_MU_CNT {2} \
#     CONFIG.C_PROBE9_MU_CNT {2} \
#     CONFIG.C_PROBE10_MU_CNT {2} \
#     CONFIG.C_PROBE11_MU_CNT {2} \
#     CONFIG.C_PROBE12_MU_CNT {2} \
#     CONFIG.C_PROBE13_MU_CNT {2} \
#     CONFIG.C_PROBE14_MU_CNT {2} \
#     CONFIG.C_PROBE15_MU_CNT {2} \
#     CONFIG.C_PROBE16_MU_CNT {2} \
# ] [get_ips ila_ctrl_slv]
