`ifndef AXI_INTF_SV_LOCAL
`define AXI_INTF_SV_LOCAL

`timescale 1ns / 1ps

import lynxTypes::*;
import reader_pkg::*;

interface AXI4SC #(
	parameter AXI4S_DATA_BITS = AXI_DATA_BITS,
	parameter AXICONFIG_WIDTH = CONFIG_WIDTH
) (
    input  logic aclk
);

typedef logic [AXI4S_DATA_BITS-1:0] data_t;
typedef logic [AXI4S_DATA_BITS/8-1:0] keep_t;
typedef logic [AXICONFIG_WIDTH-1:0] config_t;

data_t          tdata;
keep_t  		tkeep;
config_t  		tconfig;
logic           tlast;
logic           tready;
logic           tvalid;

// Tie off unused master signals
task tie_off_m ();
    tdata      = 0;
    tconfig      = 0;
    tkeep      = 0;
    tlast     = 1'b0;
    tvalid     = 1'b0;
endtask

// Tie off unused slave signals
task tie_off_s ();
    tready     = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	input tready,
	output tdata, tconfig, tkeep, tlast, tvalid
);

// Slave
modport s (
    import tie_off_s,
    input tdata, tconfig, tkeep, tlast, tvalid,
    output tready
);

endinterface

`endif