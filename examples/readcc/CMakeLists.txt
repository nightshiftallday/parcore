cmake_minimum_required(VERSION 3.10)
project(readcc)

add_executable(readcc main.cpp)

option(ENABLE_SIMULATION "Include the simulation version of Coyote" OFF)

if (ENABLE_SIMULATION)
  add_subdirectory(../../coyote/sim/sw coyote)
  target_compile_definitions(readcc PRIVATE ENABLE_SIMULATION)
else ()
  add_subdirectory(../../coyote/sw coyote)
endif ()

add_subdirectory(../../libstf/software libstf)

target_link_libraries(readcc PRIVATE Coyote)
target_include_directories(readcc PRIVATE ${COYOTE_INCLUDE_DIRS})

set(PARCORE_INCLUDE_CPU ON)
add_subdirectory(../../software parcore)
target_link_libraries(readcc PUBLIC Parcore)
target_include_directories(readcc PRIVATE ${PARCORE_INCLUDE_DIRS})

target_link_libraries(readcc PUBLIC libstf)
target_include_directories(readcc PRIVATE ${LIBSTF_INCLUDE_DIRS})

find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(readcc PUBLIC Boost::program_options)
target_include_directories(readcc PUBLIC ${ARROW_INCLUDE_DIRS})

find_package(Arrow REQUIRED)
target_link_libraries(readcc PRIVATE Arrow::arrow_shared)
target_include_directories(readcc PRIVATE ${ARROW_INCLUDE_DIRS})
