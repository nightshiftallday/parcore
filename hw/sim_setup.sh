#!/bin/bash

# cp cr_sim.tcl.in ../coyote/scripts
# cp cr_user.tcl.in ../coyote/scripts
rm -r build_sim
rm -r sim/cocotb_build
mkdir build_sim
cd build_sim
/usr/bin/cmake ..
make project
make sim
