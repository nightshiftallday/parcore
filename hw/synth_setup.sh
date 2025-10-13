#!/bin/bash

# cp cr_sim.tcl.in ../coyote/scripts
# cp cr_user.tcl.in ../coyote/scripts
rm -rf build_syn/
mkdir build_syn
cd build_syn
/usr/bin/cmake ..
make project
nohup make bitgen &> bitgen.log &
