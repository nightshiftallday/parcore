#pragma once

#include "metadata.hpp"
#include <string>

namespace parcore {
namespace metadata {

/**
 * Opens the `.parquet.meta` file at the given path and parses the metadata
 * contained therein.
 */
Metadata from_file(const std::string &path);

} // namespace metadata
} // namespace parcore
