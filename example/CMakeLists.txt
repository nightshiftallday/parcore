cmake_minimum_required(VERSION 3.10)
project(example)

add_executable(example main.cpp parcore.cpp)

find_package(Arrow REQUIRED)
find_package(Parquet REQUIRED)
find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(example PUBLIC 
    Arrow::arrow_shared
    Parquet::parquet_shared
    Boost::program_options
)
target_include_directories(example PUBLIC ${ARROW_INCLUDE_DIRS})

find_package(Coyote REQUIRED)
target_link_libraries(example PUBLIC ${COYOTE_LIBRARIES})
target_include_directories(example PUBLIC ${COYOTE_INCLUDE_DIRS})
