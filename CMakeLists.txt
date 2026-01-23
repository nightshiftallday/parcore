cmake_minimum_required(VERSION 3.0)
project(parcore)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/coyote/)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

find_package(CoyoteHW REQUIRED)

set(COMP_CORES 32)
set(N_REGIONS 1)
set(BUILD_OPT 1)
set(EN_STRM 1)
set(N_STRM_AXI 1)
set(FDEV_NAME u55c)
set(DEBUG 1)

validation_checks_hw()

load_apps (
    VFPGA_C0_0 "src libstf/hardware/src vhsnunzip/src"
)

create_hw()
