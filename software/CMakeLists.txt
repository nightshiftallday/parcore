cmake_minimum_required(VERSION 3.16)
project(Parcore
  DESCRIPTION "Hardware Parquet De- and Encoder"
  VERSION 0.1.0
  LANGUAGES CXX
)

option(PARCORE_INCLUDE_CPU "Bundles the CPU helper code to parse parquet files on the CPU from memory using Arrow's parquet parser" OFF)
option(PARCORE_WITH_PROFILING "Include profling code around expensive calls to determine where time is being spent" OFF)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(Parcore)
set_target_properties(Parcore PROPERTIES OUTPUT_NAME "parcore")

include(parcore/sources.cmake)
target_sources(Parcore PRIVATE ${PARCORE_SOURCES})
target_include_directories(Parcore
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/parcore>
)

include(parcore/metadata/sources.cmake)
target_sources(Parcore PRIVATE ${PARCORE_METADATA_SOURCES})

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR) 
    add_subdirectory(../coyote/sw coyote)
else()
    if(NOT TARGET Coyote)
        message(FATAL_ERROR "When Parcore is a subproject, parent must provide Coyote")
    endif()
endif()
target_link_libraries(Parcore PRIVATE Coyote)
target_include_directories(Parcore PRIVATE ${COYOTE_INCLUDE_DIRS})

add_subdirectory(../libstf/software libstf)
target_link_libraries(Parcore PRIVATE libstf)
target_include_directories(Parcore PRIVATE ${LIBSTF_INCLUDE_DIRS})

if (PARCORE_INCLUDE_CPU)
  find_package(Parquet REQUIRED)
  find_package(Arrow REQUIRED)

  target_link_libraries(Parcore PRIVATE Arrow::arrow_shared)
  target_link_libraries(Parcore PRIVATE Parquet::parquet_shared)
  target_include_directories(Parcore PRIVATE ${ARROW_INCLUDE_DIRS})
  target_include_directories(Parcore PRIVATE ${PARQUET_INCLUDE_DIRS})

  include(parcore/cpu/sources.cmake)
  target_sources(Parcore PRIVATE ${PARCORE_CPU_SOURCES})
endif()

if (PARCORE_WITH_PROFILING)
    find_package(caliper REQUIRED)
    target_compile_definitions(Parcore PRIVATE PARCORE_WITH_PROFILING)

    target_link_libraries(Parcore PRIVATE caliper)
    target_include_directories(Parcore PRIVATE ${CALIPER_INCLUDE_DIR})
endif()

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
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/parcore
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
