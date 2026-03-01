#pragma once

#include <cstdint>
#include <istream>
#include <optional>
#include <vector>

#include <arrow/type.h>
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
std::shared_ptr<arrow::DataType> to_arrow_type(const Type &typ);

struct Page {
  Encoding encoding;
  uint64_t offset;
  uint64_t size;
  uint64_t num_values;

  static Page from(std::istream &is);
  bool operator==(const Page &rhs) const;
};

struct ColumnChunk {
  Type type;
  uint64_t num_values;
  uint64_t hybrid_num_values;
  Compression compression;

  std::optional<Page> dictionary;
  std::vector<Page> data;

  static ColumnChunk from(std::istream &is);
  bool operator==(const ColumnChunk &rhs) const;
};

struct RowGroup {
  std::vector<ColumnChunk> chunks;

  static RowGroup from(std::istream &is);
  bool operator==(const RowGroup &rhs) const;
};

struct Metadata {
  std::vector<std::string> column_names;
  std::vector<RowGroup> groups;

  static Metadata from(std::istream &is);
  bool operator==(const Metadata &rhs) const;
};

namespace utils {
/**
 * Combines the hash of 'v' into the 'seed'.
 */
template <typename T> inline void hash_combine(std::size_t &seed, const T &v) {
  std::hash<T> hasher;
  seed ^= hasher(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
}

/**
 * Overload for containers (like std::vector).
 * Iterates through elements and combines their hashes.
 */
template <typename T>
inline void hash_range(std::size_t &seed, const T &container) {
  for (const auto &item : container) {
    hash_combine(seed, item);
  }
}
} // namespace utils

} // namespace metadata
}; // namespace parcore

namespace std {

using parcore::metadata::utils::hash_combine;

template <> struct hash<parcore::metadata::Page> {
  std::size_t operator()(const parcore::metadata::Page &p) const {
    size_t seed = 0;

    hash_combine(seed, p.encoding);
    hash_combine(seed, p.offset);
    hash_combine(seed, p.size);
    hash_combine(seed, p.num_values);

    return seed;
  }
};

template <> struct hash<parcore::metadata::ColumnChunk> {
  std::size_t operator()(const parcore::metadata::ColumnChunk &cc) const {
    size_t seed = 0;

    hash_combine(seed, cc.type);
    hash_combine(seed, cc.num_values);
    hash_combine(seed, cc.hybrid_num_values);
    hash_combine(seed, cc.compression);
    hash_combine(seed, cc.dictionary);

    for (auto page : cc.data)
      hash_combine(seed, page);

    return seed;
  }
};

template <> struct hash<parcore::metadata::RowGroup> {
  std::size_t operator()(const parcore::metadata::RowGroup &rg) const {
    size_t seed = 0;

    for (auto cc : rg.chunks)
      hash_combine(seed, cc);

    return seed;
  }
};

template <> struct hash<parcore::metadata::Metadata> {
  std::size_t operator()(const parcore::metadata::Metadata &meta) const {
    size_t seed = 0;

    for (auto col_name : meta.column_names)
      hash_combine(seed, col_name);

    for (auto rg : meta.groups)
      hash_combine(seed, rg);

    return seed;
  }
};

} // namespace std
