cmake_minimum_required(VERSION 3.16)
project(yapr)

include(ExternalProject)
include(FetchContent)

# C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(DEBUG "Enable debug messages and writing the output to the filesystem" ON)
option(WITH_MAXIMUS "Enable Maximus" OFF)
option(USE_HUGEPAGES "Use huge pages for Coyote memory allocation" OFF)

FetchContent_Declare(
  CLI11
  GIT_REPOSITORY https://github.com/CLIUtils/CLI11.git
  GIT_TAG v2.3.2  # or the latest version
)

FetchContent_MakeAvailable(CLI11)

# Arrow and Parquet
ExternalProject_Add(arrow
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/arrow/cpp
    CMAKE_ARGS
        -DARROW_BUILD_STATIC=ON
        -DARROW_BUILD_SHARED=OFF
        -DARROW_PARQUET=ON
        -DARROW_BUILD_TESTS=OFF
        -DARROW_WITH_ZSTD=ON
        -DARROW_WITH_SNAPPY=ON
        -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/arrow_install
    BUILD_ALWAYS 0
)

add_library(parquet_thrift
    thrift/parquet_types.cpp
    thrift/parquet_types.h
)
target_include_directories(parquet_thrift PRIVATE
    ${CMAKE_BINARY_DIR}/arrow-prefix/src/arrow-build/thrift_ep-install/include
    ${CMAKE_BINARY_DIR}/arrow_install/include
)
target_link_libraries(parquet_thrift PRIVATE
    ${CMAKE_BINARY_DIR}/arrow-prefix/src/arrow-build/thrift_ep-install/lib/libthrift.a
)
add_dependencies(parquet_thrift arrow)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/coyote/)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

# add_definitions(-DVERBOSE_DEBUG_3)

find_package(CoyoteSW REQUIRED)

# Configure huge pages support
if(USE_HUGEPAGES)
    message(STATUS "Huge pages enabled - getMem will use HPF allocation")
    add_definitions(-DUSE_HUGEPAGES)
else()
    message(STATUS "Huge pages disabled - getMem will use REG allocation")
endif()

# Set paths to where Maximus's scripts install dependencies
set(CMAKE_PREFIX_PATH 
    "$ENV{HOME}/arrow_install;
     $ENV{HOME}/taskflow_install;
     $ENV{HOME}/coyote_install;
     $ENV{HOME}/jemalloc_install;
     ${CMAKE_PREFIX_PATH}" 
    CACHE STRING "" FORCE)
set(COYOTE_LIBRARIES "$ENV{HOME}/coyote_install/lib/libcoyote.so" CACHE STRING "" FORCE)
set(COYOTE_INCLUDE_DIRS "$ENV{HOME}/coyote_install/include" CACHE STRING "" FORCE)
set(COYOTE_FOUND TRUE CACHE BOOL "" FORCE)

set(JEMALLOC_LIBRARIES "$ENV{HOME}/jemalloc_install/lib/libjemalloc.a" CACHE STRING "" FORCE)
set(JEMALLOC_INCLUDE_DIRS "$ENV{HOME}/jemalloc_install/include" CACHE STRING "" FORCE)
set(JEMALLOC_FOUND TRUE CACHE BOOL "" FORCE)

set(MAXIMUS_WITH_FPGA ON CACHE BOOL "" FORCE)
set(MAXIMUS_WITH_TESTS OFF CACHE BOOL "" FORCE)
set(MAXIMUS_WITH_EXAMPLES OFF CACHE BOOL "" FORCE)
set(MAXIMUS_WITH_BENCHMARKS OFF CACHE BOOL "" FORCE)
set(MAXIMUS_WITH_GPU OFF CACHE BOOL "" FORCE)
set(MAXIMUS_WITH_PROFILING OFF CACHE BOOL "" FORCE)
set(MAXIMUS_WITH_SANITIZERS OFF CACHE BOOL "" FORCE)

if (WITH_MAXIMUS)
    add_subdirectory(maximus)
endif()

# SW
add_subdirectory(sw)

