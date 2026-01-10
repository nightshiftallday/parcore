cmake_minimum_required(VERSION 3.10)
project(benchmark)

add_executable(benchmark main.cpp)

set(PARCORE_INCLUDE_CPU ON)
add_subdirectory(../../software parcore)
target_link_libraries(benchmark PUBLIC Parcore)
target_include_directories(benchmark PRIVATE ${PARCORE_INCLUDE_DIRS})

target_link_libraries(benchmark PUBLIC libstf)
target_include_directories(benchmark PRIVATE ${LIBSTF_INCLUDE_DIRS})

find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(benchmark PUBLIC Boost::program_options)
target_include_directories(benchmark PUBLIC ${ARROW_INCLUDE_DIRS})

find_package(Arrow REQUIRED)
find_package(Parquet REQUIRED)
target_link_libraries(benchmark PRIVATE Arrow::arrow_shared Parquet::parquet_shared)
target_include_directories(benchmark PRIVATE ${ARROW_INCLUDE_DIRS})

target_link_libraries(benchmark PRIVATE Coyote)
target_include_directories(benchmark PRIVATE ${COYOTE_INCLUDE_DIRS})
