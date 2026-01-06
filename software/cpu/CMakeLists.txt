add_library(ParcoreCpu cpu.cpp)
target_include_directories(ParcoreCpu PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/parcore/cpu>
)
set_target_properties(ParcoreCpu PROPERTIES OUTPUT_NAME "parcorecpu")

find_package(Arrow REQUIRED)
find_package(Parquet REQUIRED)
target_link_libraries(ParcoreCpu PUBLIC Arrow::arrow_shared Parquet::parquet_shared)
target_include_directories(ParcoreCpu PUBLIC ${ARROW_INCLUDE_DIRS})

add_library(Parcore::Cpu ALIAS ParcoreCpu)

include(GNUInstallDirs)

# Install the library
install(TARGETS ParcoreCpu
  EXPORT ParcoreCpuTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install headers
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/parcore/cpu
    FILES_MATCHING PATTERN "*.hpp"
)

# Export package configuration
install(EXPORT ParcoreCpuTargets
    FILE ParcoreCpuTargets.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/parcore
)

# Generate CMake package configuration files
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/ParcoreCpuConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)
