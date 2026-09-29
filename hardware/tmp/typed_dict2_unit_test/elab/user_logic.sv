`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

// Compile-only stand-in for the design_user_logic module Coyote generates from
// libstf/coyote/hw/templates/common/user_logic_tmplt.txt (streams enabled, no memory or network),
// with vfpga_top.svh resolved through the include path.
module design_user_logic_c0_0 (
    AXI4L.s    axi_ctrl,
    metaIntf.m notify,
    metaIntf.m sq_rd,
    metaIntf.m sq_wr,
    metaIntf.s cq_rd,
    metaIntf.s cq_wr,
    AXI4SR.s   axis_host_recv [N_STRM_AXI],
    AXI4SR.m   axis_host_send [N_STRM_AXI],
    input  wire      aclk,
    input  wire[0:0] aresetn
);

`include "vfpga_top.svh"

endmodule

module elab_top;

logic       aclk = 0;
logic [0:0] aresetn = 0;

AXI4L                  axi_ctrl (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(irq_not_t)) notify (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(req_t)) sq_rd (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(req_t)) sq_wr (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(ack_t)) cq_rd (.aclk(aclk), .aresetn(aresetn));
metaIntf #(.STYPE(ack_t)) cq_wr (.aclk(aclk), .aresetn(aresetn));
AXI4SR                 axis_host_recv [N_STRM_AXI] (.aclk(aclk), .aresetn(aresetn));
AXI4SR                 axis_host_send [N_STRM_AXI] (.aclk(aclk), .aresetn(aresetn));

design_user_logic_c0_0 dut (.*);

endmodule
