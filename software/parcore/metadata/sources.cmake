set(PARCORE_METADATA_SOURCES
    parcore/metadata/metadata.cpp
    parcore/metadata/utils.cpp
)

add_executable(parcore-metaread parcore/metadata/parcore-metaread.cpp)
target_link_libraries(parcore-metaread PRIVATE Parcore)
target_include_directories(parcore-metaread PRIVATE parcore/)
