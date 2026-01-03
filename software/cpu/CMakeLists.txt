cmake_minimum_required(VERSION 3.16)
project(parcore_cpu)

add_library(parcore_cpu cpu.cpp)
target_include_directories(parcore_cpu PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

find_package(Arrow REQUIRED)
find_package(Parquet REQUIRED)
target_link_libraries(parcore_cpu PUBLIC Arrow::arrow_shared Parquet::parquet_shared)
target_include_directories(parcore_cpu PUBLIC ${ARROW_INCLUDE_DIRS})
