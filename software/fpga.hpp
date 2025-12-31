#pragma once

#include "metadata/metadata.hpp"

#include <array>
#include <stdint.h>

namespace parcore {

const constexpr uint8_t PARCORE_COMMAND_SIZE = 64;

typedef std::array<uint8_t, PARCORE_COMMAND_SIZE> ParcoreCommand;

/**
 * Generates the command(s) (set of bytes) to submit to the hardware through the
 * host stream so that the provided page(s) can be parsed.
 *
 * The page(s) containing the necessary data must then be submitted through
 * the other host stream to kick off the processing.
 */
std::vector<ParcoreCommand>
commands_for_column_chunk(const metadata::ColumnChunk &chunk);

/**
 * Returns the number of output bytes for the given data type of page values.
 */
size_t type_data_size(metadata::Type type);

} // namespace parcore
