#pragma once

#include "metadata.hpp"
#include <string>

namespace parcore {
namespace metadata {

/**
 * Opens the Parquet file at the given path and extracts column chunk metadata
 * from the footer.
 */
Metadata from_file(const std::string &path);

} // namespace metadata
} // namespace parcore
