#pragma once

#include <istream>
#include <optional>
#include <stdexcept>
#include <stdint.h>
#include <vector>

namespace parcore {
namespace metadata {

enum class Encoding : uint8_t { PLAIN = 0, HYBRID = 1 };

enum class Compression : uint8_t { RAW = 0, SNAPPY = 1 };

enum class Type : uint8_t {
  BYTE = 0,
  INT32 = 1,
  INT64 = 2,
  FLOAT = 3,
  DOUBLE = 4,
};

static void read_exact(std::istream &is, void *dst, size_t n) {
  if (!is.read(reinterpret_cast<char *>(dst), n))
    throw std::runtime_error("unexpected EOF");
}

struct Page {
  Encoding encoding;
  uint64_t offset;
  uint64_t size;

  static Page from(std::istream &is) {
    Page p;
    read_exact(is, &p.encoding, sizeof(uint8_t));
    read_exact(is, &p.offset, sizeof(uint64_t));
    read_exact(is, &p.size, sizeof(uint64_t));
    return p;
  }
};

struct ColumnChunk {
  Type type;
  uint64_t num_values;
  Compression compression;

  std::optional<Page> dictionary;
  Page data;

  static ColumnChunk from(std::istream &is) {
    ColumnChunk c;
    read_exact(is, &c.type, sizeof(uint8_t));
    read_exact(is, &c.num_values, sizeof(uint64_t));
    read_exact(is, &c.compression, sizeof(uint8_t));

    uint8_t has_dict;
    read_exact(is, &has_dict, sizeof(uint8_t));
    if (has_dict)
      c.dictionary = Page::from(is);

    c.data = Page::from(is);
    return c;
  }
};

struct RowGroup {
  std::vector<ColumnChunk> chunks;

  static RowGroup from(std::istream &is) {
    RowGroup g;
    uint32_t n;
    read_exact(is, &n, sizeof(uint32_t));
    g.chunks.reserve(n);
    for (uint32_t i = 0; i < n; ++i)
      g.chunks.push_back(ColumnChunk::from(is));
    return g;
  }
};

struct Metadata {
  std::vector<RowGroup> groups;

  static Metadata from(std::istream &is) {
    Metadata m;
    uint32_t n;
    read_exact(is, &n, sizeof(uint32_t));
    m.groups.reserve(n);
    for (uint32_t i = 0; i < n; ++i)
      m.groups.push_back(RowGroup::from(is));
    return m;
  }
};

} // namespace metadata
}; // namespace parcore
