#pragma once

#include <parcore/metadata/metadata.hpp>

#include <array>
#include <memory>
#include <parquet/types.h>

namespace parcore {

const constexpr uint8_t PARCORE_COMMAND_SIZE = 64;

typedef std::array<uint8_t, PARCORE_COMMAND_SIZE> ParcoreCommand;

enum class PageType : uint8_t {
  DATA = 0,
  DICT = 1,
};

/**
 * Generates the command (set of bytes) to submit to the hardware through the
 * host stream so that the provided page can be parsed.
 *
 * The page containing the necessary data must then be submitted through
 * the other host stream to kick off the processing.
 */
ParcoreCommand command_for_column_chunk_page(const metadata::ColumnChunk &chunk,
                                             const metadata::Page &page,
                                             PageType page_type);

/**
 * Returns the number of output bytes for the given data type of page values.
 */
size_t type_data_size(metadata::Type typ);

/**
 * Returns the corresponding Arrow Type for the given data type.
 */
std::shared_ptr<arrow::DataType> type_to_arrow(metadata::Type typ);

} // namespace parcore
