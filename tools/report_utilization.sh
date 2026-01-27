#!/bin/bash

WORKING_DIR=$(pwd)/tools

vivado -mode batch -source $WORKING_DIR/tcl/utilization_report.tcl