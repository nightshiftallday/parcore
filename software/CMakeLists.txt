cmake_minimum_required(VERSION 3.16)
project(parcore LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(parcore fpga.cpp utils.cpp)

target_include_directories(parcore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

option(INCLUDE_CPU "Bundles the CPU helper code to parse parquet files on the CPU from memory using Arrow's parquet parser" OFF)

add_subdirectory(metadata)
target_link_libraries(parcore PUBLIC parcore_metadata)

if (INCLUDE_CPU)
  add_subdirectory(cpu)
  target_link_libraries(parcore PUBLIC parcore_cpu)
endif(INCLUDE_CPU)
