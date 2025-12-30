cmake_minimum_required(VERSION 3.16)
project(parcore LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(parcore parcore.cpp)

target_include_directories(parcore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

add_subdirectory(metadata)
target_link_libraries(parcore PUBLIC parcore_metadata)
