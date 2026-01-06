add_library(ParcoreMetadata src/metadata.cpp src/utils.cpp)
target_include_directories(ParcoreMetadata PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/parcore/metadata>
)
set_target_properties(ParcoreMetadata PROPERTIES OUTPUT_NAME "parcoremetadata")

add_executable(parcore-metaread src/parcore-metaread.cpp)
target_link_libraries(parcore-metaread PRIVATE ParcoreMetadata)

add_library(Parcore::Metadata ALIAS ParcoreMetadata)

include(GNUInstallDirs)

# Install the library
install(TARGETS ParcoreMetadata
    EXPORT ParcoreMetadataTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install headers
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/parcore/metadata
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/parcore/metadata
    FILES_MATCHING PATTERN "*.hpp"
)

# Export package configuration
install(EXPORT ParcoreMetadataTargets
    FILE ParcoreMetadataTargets.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/parcore
)

# Generate CMake package configuration files
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/ParcoreMetadataConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)
