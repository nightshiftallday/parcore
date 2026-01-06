#pragma once

#include <arrow/array.h>
#include <coyote/cThread.hpp>
#include <cstdint>
#include <parcore/metadata/metadata.hpp>

namespace parcore {
namespace utils {

/*
 * Sends the necessary commands and data to the parcore hardware decoder to
 * parse the provided column chunk.
 *
 * NOTE: This assumes that the data in `data` has already been mapped with
 * `userMap` in the provided cThread.
 */
std::shared_ptr<arrow::ChunkedArray>
read_column_chunk(std::shared_ptr<coyote::cThread> cthread,
                  arrow::MemoryPool *pool, const metadata::Metadata &meta,
                  const std::vector<uint8_t> data, size_t chunk, size_t column);

} // namespace utils
} // namespace parcore
