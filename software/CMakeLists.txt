cmake_minimum_required(VERSION 3.16)
project(Parcore
  DESCRIPTION "Hardware Parquet De- and Encoder"
  VERSION 0.1.0
  LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(Parcore src/fpga.cpp)
target_include_directories(Parcore
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/parcore>
)
set_target_properties(Parcore PROPERTIES OUTPUT_NAME "parcore")

find_package(Arrow REQUIRED)
target_link_libraries(Parcore PUBLIC Arrow::arrow_shared)
target_include_directories(Parcore PUBLIC ${ARROW_INCLUDE_DIRS})

add_subdirectory(metadata)
target_link_libraries(Parcore PUBLIC Parcore::Metadata)

option(INCLUDE_CPU "Bundles the CPU helper code to parse parquet files on the CPU from memory using Arrow's parquet parser" OFF)
option(INCLUDE_COYOTE "Includes some utilities to submit work to the design using the Coyote APIs" ON)

if (INCLUDE_CPU)
  add_subdirectory(cpu)
  target_link_libraries(Parcore PUBLIC Parcore::Cpu)
endif(INCLUDE_CPU)

if (INCLUDE_COYOTE)
  target_sources(Parcore PRIVATE src/utils.cpp)

  add_subdirectory(../coyote/sw coyote)
  target_link_libraries(Parcore PRIVATE Coyote)
  target_include_directories(Parcore PRIVATE ${COYOTE_INCLUDE_DIRS})
endif(INCLUDE_COYOTE)

include(GNUInstallDirs)

# Install the library
install(TARGETS Parcore
    EXPORT ParcoreTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install headers
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/parcore
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/parcore
    FILES_MATCHING PATTERN "*.hpp"
)

# Export package configuration
install(EXPORT ParcoreTargets
    FILE ParcoreTargets.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/parcore
)

# Generate CMake package configuration files
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/ParcoreConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)
