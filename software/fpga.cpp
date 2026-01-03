#include "fpga.hpp"
#include "metadata/metadata.hpp"

#include <arrow/type.h>
#include <arrow/type_fwd.h>
#include <cstring>
#include <optional>

using parcore::metadata::ColumnChunk;
using parcore::metadata::Compression;
using parcore::metadata::Page;
using parcore::metadata::Type;

namespace parcore {

inline uint8_t type_to_hardware(Type typ) {
  switch (typ) {
  case Type::BYTE:
    return 0;
  case Type::INT32:
    return 1;
  case Type::INT64:
    return 2;
  case Type::FLOAT:
    return 3;
  case Type::DOUBLE:
    return 4;
  default:
    throw std::runtime_error("Unexpected metadata type to convert to hardware");
  }
}

inline uint8_t page_type_to_hardware(PageType page_type) {
  return static_cast<uint8_t>(page_type);
}

inline uint8_t compression_to_hardware(Compression compression) {
  switch (compression) {
  case Compression::RAW:
    return 0;
  case Compression::SNAPPY:
    return 1;
  default:
    throw std::runtime_error(
        "Unexpected metadata compression to convert to hardware");
  }
}

ParcoreCommand command_for_column_chunk(const ColumnChunk &chunk,
                                        const Page &page, PageType page_type) {
  ParcoreCommand cmd = {0};

  cmd[41] = type_to_hardware(chunk.type);
  cmd[42] = page_type_to_hardware(page_type);

  if (page_type != PageType::DICT) {
    uint32_t encoded_num_values = chunk.num_values;
    std::memcpy(&cmd[43], &encoded_num_values, sizeof(encoded_num_values));
  }

  cmd[47] = compression_to_hardware(chunk.compression);

  return cmd;
}

size_t type_data_size(Type typ) {
  switch (typ) {
  case Type::BYTE:
    return 1;
  case Type::INT32:
  case Type::FLOAT:
    return 4;
  case Type::INT64:
  case Type::DOUBLE:
    return 8;
  default:
    throw std::runtime_error("Unexpected metadata type while getting its size");
  }
}

std::shared_ptr<arrow::DataType> type_to_arrow(metadata::Type typ) {
  switch (typ) {
  case Type::BYTE:
    return arrow::boolean(); // NOTE: we're assuming one byte represents a
                             // boolean
  case Type::INT32:
    return arrow::int32();
  case Type::FLOAT:
    return arrow::float32();
  case Type::INT64:
    return arrow::int64();
  case Type::DOUBLE:
    return arrow::float64();
  default:
    throw std::runtime_error("Unexpected metadata type while getting its size");
  }
}

} // namespace parcore
