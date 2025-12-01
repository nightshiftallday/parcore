#pragma once

#include <cstdlib>
#include <parquet/arrow/reader.h>

namespace parcore {

enum class Compression : uint8_t { RAW = 0, SNAPPY = 1 };

inline std::ostream &operator<<(std::ostream &os, Compression c) {
  switch (c) {
  case Compression::RAW:
    return os << "RAW";
  case Compression::SNAPPY:
    return os << "SNAPPY";
  }
  return os;
}

struct Page {
  std::vector<uint8_t> data;
  uint32_t num_values;
  std::vector<uint8_t> values;
};

enum class Type : uint8_t {
  BYTE_T = 0,
  INT32_T = 1,
  INT64_T = 2,
  FLOAT_T = 3,
  DOUBLE_T = 4,
};

Type data_type(parquet::Type::type);

inline std::ostream &operator<<(std::ostream &os, Type t) {
  switch (t) {
  case Type::BYTE_T:
    return os << "BYTE_T";
  case Type::INT32_T:
    return os << "INT32_T";
  case Type::INT64_T:
    return os << "INT64_T";
  case Type::FLOAT_T:
    return os << "FLOAT_T";
  case Type::DOUBLE_T:
    return os << "DOUBLE_T";
  }
  return os;
}

struct Column {
  uint32_t id;
  std::string name;
  Compression compression;
  Type data_type;

  Page dictionary;
  std::vector<Page> pages;
};

std::vector<Column> read_parquet_pages(const std::string &);

enum class PageType : uint8_t {
  HYBRID = 0,
  DICT = 1,
};

inline std::ostream &operator<<(std::ostream &os, PageType pt) {
  switch (pt) {
  case PageType::HYBRID:
    return os << "HYBRID";
  case PageType::DICT:
    return os << "DICT";
  }
  return os;
}

typedef std::array<uint8_t, 64> cmd_t;

cmd_t cmd(PageType, Type, uint32_t, Compression);

uint32_t data_size(Type);

} // namespace parcore
