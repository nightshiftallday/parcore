cmake_minimum_required(VERSION 3.16)
project(parcore
  DESCRIPTION "Hardware Parquet De- and Encoder"
  VERSION 0.1.0
  LANGUAGES CXX
)

option(PARCORE_WITHOUT_ARROW "Build ParCore without any Apache Arrow dependency. When ON (default), the Arrow-returning Readers (FileReader, PreloadFileReader, MultiReader, the adaptor, and the CPU/hybrid Parquet parser) are excluded and Arrow is not linked." ON)

# Default to a Release build (optimized) unless the user specifies otherwise.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build." FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
        "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT TARGET Coyote)
    find_package(Coyote QUIET)
    if(NOT Coyote_FOUND)
        add_subdirectory(../libstf/coyote/sw coyote)
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
    parcore/column_chunk_decoder.cpp
    parcore/hardware_reader.cpp
    parcore/memory_reader.cpp

    parcore/metadata/metadata.cpp
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

if (PARCORE_WITHOUT_ARROW)
    message(STATUS "Building ParCore without Apache Arrow")
else()
    message(STATUS "Building ParCore with Apache Arrow and the Parquet reader stack")

    find_package(Arrow REQUIRED)
    target_link_libraries(parcore PUBLIC Arrow::arrow_shared)

    find_package(Parquet REQUIRED)
    target_link_libraries(parcore PRIVATE Parquet::parquet_shared)
    target_include_directories(parcore PRIVATE ${PARQUET_INCLUDE_DIRS})

    # Arrow-returning Readers and the CPU/hybrid parquet parser.
    target_sources(parcore PRIVATE
        parcore/file_reader.cpp
        parcore/preload_file_reader.cpp
        parcore/adaptor.cpp
        parcore/multi_reader.cpp

        parcore/cpu/cpu.cpp
        parcore/cpu/cpu_reader.cpp
        parcore/hybrid_reader.cpp
        parcore/metadata/utils.cpp
    )
endif()

# Install the library
install(TARGETS parcore
    EXPORT parcoreTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install headers. The Arrow-coupled Reader/adaptor headers are only installed
# when ParCore is built with Arrow; the Arrow-free build ships only the headers
# that don't pull in Arrow.
set(PARCORE_ARROW_HEADERS
    PATTERN "reader.hpp" EXCLUDE
    PATTERN "adaptor.hpp" EXCLUDE
    PATTERN "file_reader.hpp" EXCLUDE
    PATTERN "preload_file_reader.hpp" EXCLUDE
    PATTERN "multi_reader.hpp" EXCLUDE
    PATTERN "hybrid_reader.hpp" EXCLUDE
    PATTERN "utils.hpp" EXCLUDE
    PATTERN "cpu" EXCLUDE
)
if (PARCORE_WITHOUT_ARROW)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/parcore/"
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/parcore
        FILES_MATCHING PATTERN "*.hpp"
        ${PARCORE_ARROW_HEADERS}
    )
else()
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/parcore/"
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/parcore
        FILES_MATCHING PATTERN "*.hpp"
    )
endif()

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
