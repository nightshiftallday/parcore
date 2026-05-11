cmake_minimum_required(VERSION 3.16)
project(parcore
  DESCRIPTION "Hardware Parquet De- and Encoder"
  VERSION 0.1.0
  LANGUAGES CXX
)

option(PARCORE_INCLUDE_CPU "Bundles the CPU helper code to parse parquet files on the CPU from memory using Arrow's parquet parser" OFF)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT TARGET Coyote)
    find_package(Coyote QUIET)
    if(NOT Coyote_FOUND)
        add_subdirectory(../coyote/sw coyote)
    endif()
endif()
if(NOT TARGET libstf)
    find_package(libstf QUIET)
    if(NOT libstf_FOUND)
        add_subdirectory(../libstf/software libstf)
    endif()
endif()

include(GNUInstallDirs)

add_library(parcore SHARED)

target_sources(parcore PRIVATE
    parcore/configuration.cpp
    parcore/reader.cpp
    parcore/column_chunk_decoder.cpp
    parcore/hardware_reader.cpp
    parcore/file_reader.cpp
    parcore/preload_file_reader.cpp
    parcore/memory_reader.cpp
    parcore/adaptor.cpp

    parcore/multi_reader.cpp

    parcore/metadata/metadata.cpp
    parcore/metadata/utils.cpp
)
target_include_directories(parcore
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/parcore>
)

target_link_libraries(parcore PRIVATE Coyote)
target_include_directories(parcore PRIVATE ${COYOTE_INCLUDE_DIRS})
target_link_libraries(parcore PRIVATE libstf)
target_include_directories(parcore PRIVATE ${LIBSTF_INCLUDE_DIRS})

find_package(Arrow REQUIRED)
target_link_libraries(parcore PUBLIC Arrow::arrow_shared)

if (PARCORE_INCLUDE_CPU)
    find_package(Parquet REQUIRED)
    target_link_libraries(parcore PRIVATE Parquet::parquet_shared)
    target_include_directories(parcore PRIVATE ${PARQUET_INCLUDE_DIRS})

    message(STATUS "Adding CPU decoding support to ParCore")

    target_sources(parcore PRIVATE 
        parcore/cpu/cpu.cpp
        parcore/cpu/cpu_reader.cpp
        parcore/hybrid_reader.cpp
    )
endif()

# Metadata utility
add_executable(parcore-metaread parcore/metadata/parcore-metaread.cpp)
target_link_libraries(parcore-metaread PRIVATE parcore)
target_include_directories(parcore-metaread PRIVATE parcore/)
target_link_libraries(parcore-metaread PRIVATE libstf)
target_include_directories(parcore-metaread PRIVATE ${LIBSTF_INCLUDE_DIRS})

# Install the library
install(TARGETS parcore
    EXPORT parcoreTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install headers
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/parcore/"
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/parcore
    FILES_MATCHING PATTERN "*.hpp"
)

# Export package configuration
install(EXPORT parcoreTargets
    FILE parcoreTargets.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/parcore
)

# Generate CMake package configuration files
include(CMakePackageConfigHelpers)

configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/parcoreConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/parcoreConfig.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/parcore
)

write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/parcoreConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)

install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/parcoreConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/parcoreConfigVersion.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/parcore
)
