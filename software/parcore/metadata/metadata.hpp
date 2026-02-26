#pragma once

#include <cstdint>
#include <istream>
#include <optional>
#include <vector>

#include <libstf/common.hpp>

namespace parcore {
namespace metadata {

std::string read_string(std::istream &is);

enum class Encoding : uint8_t { PLAIN = 0, HYBRID = 1 };
std::ostream &operator<<(std::ostream &os, Encoding e);

enum class Compression : uint8_t { RAW = 0, SNAPPY = 1 };
std::ostream &operator<<(std::ostream &os, Compression c);

enum class Type : unsigned char {
  BYTE_T = 0,
  INT32_T = 1,
  INT64_T = 2,
  FLOAT_T = 3,
  DOUBLE_T = 4,
  BYTE_ARRAY = 5
};
std::ostream &operator<<(std::ostream &os, Type typ);
bool is_libstf_type(const Type &typ);
libstf::type_t to_libstf_type(const Type &typ);

struct Page {
  Encoding encoding;
  uint64_t offset;
  uint64_t size;
  uint64_t num_values;

  static Page from(std::istream &is);
};

struct ColumnChunk {
  Type type;
  uint64_t num_values;
  uint64_t hybrid_num_values;
  Compression compression;

  std::optional<Page> dictionary;
  std::vector<Page> data;

  static ColumnChunk from(std::istream &is);
};

struct RowGroup {
  std::vector<ColumnChunk> chunks;

  static RowGroup from(std::istream &is);
};

struct Metadata {
  std::vector<std::string> column_names;
  std::vector<RowGroup> groups;

  static Metadata from(std::istream &is);
};

} // namespace metadata
}; // namespace parcore
