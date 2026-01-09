cmake_minimum_required(VERSION 3.10)
project(readfile)

add_executable(readfile main.cpp)

set(PARCORE_INCLUDE_COYOTE ON)
set(PARCORE_INCLUDE_CPU ON)
add_subdirectory(../../software parcore)
target_link_libraries(readfile PUBLIC Parcore)
target_include_directories(readfile PRIVATE ${PARCORE_INCLUDE_DIRS})

target_link_libraries(readfile PUBLIC libstf)
target_include_directories(readfile PRIVATE ${LIBSTF_INCLUDE_DIRS})

find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(readfile PUBLIC Boost::program_options)
target_include_directories(readfile PUBLIC ${ARROW_INCLUDE_DIRS})

find_package(Arrow REQUIRED)
target_link_libraries(readfile PRIVATE Arrow::arrow_shared)
target_include_directories(readfile PRIVATE ${ARROW_INCLUDE_DIRS})

target_link_libraries(readfile PRIVATE Coyote)
target_include_directories(readfile PRIVATE ${COYOTE_INCLUDE_DIRS})
