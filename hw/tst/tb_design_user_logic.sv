`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * User logic
 * 
 */
module design_user_logic_c0_0 (
    AXI4L.s                     axi_ctrl,

    // NOTIFY
    metaIntf.m                  notify,

    // DESCRIPTORS
    metaIntf.m                  sq_rd, 
    metaIntf.m                  sq_wr,
    metaIntf.s                  cq_rd,
    metaIntf.s                  cq_wr,

    // HOST DATA STREAMS
    AXI4SR.s                    axis_host_recv[1],
    AXI4SR.m                    axis_host_send[1],

    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

// Include your vFPGA top logic
`include "vfpga_top.svh"


endmodule

