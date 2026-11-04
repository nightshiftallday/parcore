cmake_minimum_required(VERSION 3.0)
project(parcore)

# Dependency checkouts; the defaults are the submodules
set(LIBSTF_DIR ${CMAKE_SOURCE_DIR}/../libstf CACHE PATH "libstf checkout")
set(VHSNUNZIP_DIR ${CMAKE_SOURCE_DIR}/../vhsnunzip CACHE PATH "vhsnunzip checkout")
set(CYT_DIR ${LIBSTF_DIR}/coyote CACHE PATH "Coyote checkout")
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

find_package(CoyoteHW REQUIRED)

set(PARCORE_COMP_CORES 64 CACHE STRING "Number of parallel Vivado jobs")
set(COMP_CORES ${PARCORE_COMP_CORES})
set(PARCORE_NUM_REGIONS 1 CACHE STRING "Number of vFPGAs, each with PARCORE_NUM_DECODERS decoders")
set(N_REGIONS ${PARCORE_NUM_REGIONS})
set(BUILD_OPT 1)
set(EN_STRM 1)
set(PARCORE_NUM_DECODERS 4 CACHE STRING "Number of ColumnChunkDecoders per vFPGA, each with its own host stream")
set(N_STRM_AXI ${PARCORE_NUM_DECODERS})
set(FDEV_NAME u55c)
set(DEBUG 1)
# Enable 1 GiB huge pages in the TLB
set(TLBL_BITS 30)

validation_checks_hw()

set(VFPGA_TOP "" CACHE STRING "vFPGA top to build instead of src/vfpga_top.svh, relative to hardware/ (e.g. unit-tests/vfpga_tops/run_decoder_test.sv)")

# Coyote resolves the source directories relative to hardware/
file(RELATIVE_PATH LIBSTF_SRC_DIR ${CMAKE_SOURCE_DIR} ${LIBSTF_DIR}/hardware/src)
file(RELATIVE_PATH VHSNUNZIP_SRC_DIR ${CMAKE_SOURCE_DIR} ${VHSNUNZIP_DIR}/src)
set(VFPGA_SRC_DIRS "src ${LIBSTF_SRC_DIR} ${VHSNUNZIP_SRC_DIR}")

# Coyote takes the vFPGA top from the first source directory, so a custom top is copied into its own
# directory in the build tree that is put in front of the other source directories.
if(VFPGA_TOP)
    get_filename_component(VFPGA_TOP_FILE ${VFPGA_TOP} ABSOLUTE BASE_DIR ${CMAKE_SOURCE_DIR})
    if(NOT EXISTS ${VFPGA_TOP_FILE})
        message(FATAL_ERROR "VFPGA_TOP ${VFPGA_TOP_FILE} does not exist.")
    endif()
    configure_file(${VFPGA_TOP_FILE} ${CMAKE_BINARY_DIR}/vfpga_top/vfpga_top.svh COPYONLY)
    file(RELATIVE_PATH VFPGA_TOP_DIR ${CMAKE_SOURCE_DIR} ${CMAKE_BINARY_DIR}/vfpga_top)
    set(VFPGA_SRC_DIRS "${VFPGA_TOP_DIR} ${VFPGA_SRC_DIRS}")
endif()

# Every vFPGA gets the same design
set(APPS "")
math(EXPR LAST_REGION "${N_REGIONS} - 1")
foreach(R RANGE ${LAST_REGION})
    list(APPEND APPS VFPGA_C0_${R} "${VFPGA_SRC_DIRS}")
endforeach()
load_apps(${APPS})

create_hw()
