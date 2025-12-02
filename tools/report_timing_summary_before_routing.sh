#!/bin/bash

WORKING_DIR=$(pwd)/tools

vivado -mode batch -source $WORKING_DIR/tcl/timing_report_summary_before_routing.tcl