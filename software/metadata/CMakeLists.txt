add_library(parcore_metadata metadata.cpp utils.cpp)
target_include_directories(parcore_metadata PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

add_executable(parcore-metaread parcore-metaread.cpp)
target_link_libraries(parcore-metaread PRIVATE parcore_metadata)
