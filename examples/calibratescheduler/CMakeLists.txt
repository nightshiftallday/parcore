cmake_minimum_required(VERSION 3.10)
project(calibratescheduler)

add_executable(calibratescheduler main.cpp)

add_subdirectory(../../coyote/sw coyote)
target_link_libraries(calibratescheduler PRIVATE Coyote)
target_include_directories(calibratescheduler PRIVATE ${COYOTE_INCLUDE_DIRS})

add_subdirectory(../../libstf/software libstf)
target_link_libraries(calibratescheduler PUBLIC libstf)
target_include_directories(calibratescheduler PRIVATE ${LIBSTF_INCLUDE_DIRS})

set(PARCORE_INCLUDE_CPU ON)
add_subdirectory(../../software parcore)
target_link_libraries(calibratescheduler PUBLIC Parcore)
target_include_directories(calibratescheduler PRIVATE ${PARCORE_INCLUDE_DIRS})

find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(calibratescheduler PUBLIC Boost::program_options)
target_include_directories(calibratescheduler PUBLIC ${ARROW_INCLUDE_DIRS})

find_package(Arrow REQUIRED)
find_package(Parquet REQUIRED)
target_link_libraries(calibratescheduler PRIVATE Arrow::arrow_shared Parquet::parquet_shared)
target_include_directories(calibratescheduler PRIVATE ${ARROW_INCLUDE_DIRS})

