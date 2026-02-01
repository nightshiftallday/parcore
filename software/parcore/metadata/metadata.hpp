#pragma once

#include <cstdint>
#include <istream>
#include <optional>
#include <vector>

#include <libstf/common.hpp>

namespace parcore {
namespace metadata {

enum class Encoding : uint8_t { PLAIN = 0, HYBRID = 1 };
std::ostream &operator<<(std::ostream &os, Encoding e);

enum class Compression : uint8_t { RAW = 0, SNAPPY = 1 };
std::ostream &operator<<(std::ostream &os, Compression c);

struct Page {
  Encoding encoding;
  uint64_t offset;
  uint64_t size;

  static Page from(std::istream &is);
};

struct ColumnChunk {
  libstf::type_t type;
  uint64_t num_values;
  Compression compression;

  std::optional<Page> dictionary;
  Page data;

  static ColumnChunk from(std::istream &is);
};

struct RowGroup {
  std::vector<ColumnChunk> chunks;

  static RowGroup from(std::istream &is);
};

struct Metadata {
  std::vector<RowGroup> groups;

  static Metadata from(std::istream &is);
};

} // namespace metadata
}; // namespace parcore
