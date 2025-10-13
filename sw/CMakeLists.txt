cmake_minimum_required(VERSION 3.13)
project(yapr)

find_package(ZLIB REQUIRED)

set(TARGET_DIR "src")
message("**  Build SW")

add_library(common
    ${TARGET_DIR}/common/common.h
    ${TARGET_DIR}/common/common.cpp
)
target_include_directories(common PUBLIC
    ${TARGET_DIR}/common
    ${CMAKE_BINARY_DIR}/arrow-prefix/src/arrow-build/thrift_ep-install/include
    ${CMAKE_BINARY_DIR}/arrow_install/include
    ${CMAKE_BINARY_DIR}/../thrift
    ${CMAKE_BINARY_DIR}/../coyote/sw
    ${CMAKE_BINARY_DIR}/../coyote/sim/sw
)
message("**  Simulation directory: ${SIM_DIR}")
target_link_libraries(common PUBLIC
    Coyote
    ${CMAKE_BINARY_DIR}/arrow_install/lib/libparquet.a
    ${CMAKE_BINARY_DIR}/arrow_install/lib/libarrow.a
    ${CMAKE_BINARY_DIR}/arrow_install/lib/libarrow_bundled_dependencies.a
    pthread
    parquet_thrift
    dl
    ZLIB::ZLIB
)
if(DEBUG)
    target_compile_definitions(common PRIVATE DEBUG) 
endif()
if(DEBUG_1)
    target_compile_definitions(common PRIVATE DEBUG_1) 
endif()
if(DEBUG_2)
    target_compile_definitions(common PRIVATE DEBUG_2) 
endif()
if(DEBUG_3)
    target_compile_definitions(common PRIVATE DEBUG_3) 
endif()
if(USE_HUGEPAGES)
    target_compile_definitions(common PUBLIC USE_HUGEPAGES) 
endif()
add_dependencies(common arrow)


add_executable(cpu_reader ${TARGET_DIR}/cpu_reader/main.cpp)
# target_include_directories(cpu_reader PRIVATE
#     ${CMAKE_BINARY_DIR}/arrow_install/include
# )
target_link_libraries(cpu_reader PRIVATE
    CLI11::CLI11
    common
)
add_dependencies(cpu_reader common)


add_executable(yapr ${TARGET_DIR}/single_col_reader/main.cpp)
target_link_libraries(yapr PRIVATE common)
target_link_directories(yapr PUBLIC /usr/local/lib)
add_dependencies(yapr common)

if (WITH_MAXIMUS)
    # add_executable(test_bench ${TARGET_DIR}/test_bench/main.cpp)
    # target_link_libraries(test_bench PRIVATE common maximus)
    # target_include_directories(test_bench PRIVATE ${CMAKE_SOURCE_DIR}/maximus/src)
    # target_link_directories(test_bench PUBLIC /usr/local/lib)
    # add_dependencies(test_bench common)
    # if (DEBUG)
    #     target_compile_definitions(test_bench PRIVATE DEBUG) 
    # endif()
endif()

add_executable(simulation ${TARGET_DIR}/simulation/main.cpp)
target_link_libraries(simulation PRIVATE common)
target_link_directories(simulation PUBLIC /usr/local/lib)
add_dependencies(simulation common)


add_executable(standalone_reader_example ${TARGET_DIR}/examples/standalone_reader_example.cpp)
target_link_libraries(standalone_reader_example PRIVATE common)
target_link_directories(standalone_reader_example PUBLIC /usr/local/lib)
add_dependencies(standalone_reader_example common)

add_executable(reset_example ${TARGET_DIR}/examples/reset_example.cpp)
target_link_libraries(reset_example PRIVATE common)
target_link_directories(reset_example PUBLIC /usr/local/lib)
add_dependencies(reset_example common)

add_executable(parquet_analysis_example ${TARGET_DIR}/examples/parquet_analysis_example.cpp)
target_link_libraries(parquet_analysis_example PRIVATE common)
target_link_directories(parquet_analysis_example PUBLIC /usr/local/lib)
add_dependencies(parquet_analysis_example common)

add_executable(test_bench ${TARGET_DIR}/test_bench/main.cpp)
target_link_libraries(test_bench PRIVATE common)
target_link_directories(test_bench PUBLIC /usr/local/lib)
add_dependencies(test_bench common)

if(DEBUG)
    target_compile_definitions(cpu_reader PRIVATE DEBUG) 
    target_compile_definitions(yapr PRIVATE DEBUG) 
    target_compile_definitions(simulation PRIVATE DEBUG) 
    target_compile_definitions(standalone_reader_example PRIVATE DEBUG) 
    target_compile_definitions(reset_example PRIVATE DEBUG) 
    target_compile_definitions(parquet_analysis_example PRIVATE DEBUG) 
    target_compile_definitions(test_bench PRIVATE DEBUG) 
endif()

