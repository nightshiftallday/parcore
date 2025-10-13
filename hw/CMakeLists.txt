cmake_minimum_required(VERSION 3.0)
project(test)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/../coyote/)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

find_package(CoyoteHW REQUIRED)

# Configurable parameter for number of units
# This parameter controls both N_STRM_AXI (line 16) and NUM_UNITS in reader_pkg.sv
# Usage: cmake -DNUM_UNITS=<value> .
set(NUM_UNITS 1 CACHE STRING "Number of processing units")

set(N_REGIONS 1)
set(EN_STRM 1)
set(N_STRM_AXI ${NUM_UNITS})
set(FDEV_NAME u55c)
set(DEBUG 1)

# Generate reader_pkg.sv from template
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/reader_pkg_tmplt.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/src/hdl/reader_pkg.sv
    @ONLY
)

validation_checks_hw()

load_apps (
    VFPGA_C0_0 "src"
)

create_hw()
