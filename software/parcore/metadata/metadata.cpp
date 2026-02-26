#include <parcore/metadata/metadata.hpp>

#include <iostream>
#include <ostream>
#include <stdexcept>

namespace parcore {
namespace metadata {

std::ostream &operator<<(std::ostream &os, Type typ) {
  switch (typ) {
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
  default:
    return os << "UNEXPECTED TYPE";
  }
}

bool is_libstf_type(const Type &typ) {
  switch (typ) {
  case Type::BYTE_T:
  case Type::INT32_T:
  case Type::INT64_T:
  case Type::FLOAT_T:
  case Type::DOUBLE_T:
    return true;
  default:
    return false;
  }
}

libstf::type_t to_libstf_type(const Type &typ) {
  switch (typ) {
  case Type::BYTE_T:
    return libstf::type_t::BYTE_T;
  case Type::INT32_T:
    return libstf::type_t::INT32_T;
  case Type::INT64_T:
    return libstf::type_t::INT64_T;
  case Type::FLOAT_T:
    return libstf::type_t::FLOAT_T;
  case Type::DOUBLE_T:
    return libstf::type_t::DOUBLE_T;
  default:
    throw std::runtime_error("cannot convert type to libstf::type_t");
  }
}

std::shared_ptr<arrow::DataType> to_arrow_type(const Type &typ) {
  switch (typ) {
  case Type::BYTE_T:
    return arrow::boolean();
  case Type::INT32_T:
    return arrow::int32();
  case Type::INT64_T:
    return arrow::int64();
  case Type::FLOAT_T:
    return arrow::float32();
  case Type::DOUBLE_T:
    return arrow::float64();
  default:
    throw std::runtime_error("cannot convert type to arrow::DataType");
  }
}

std::ostream &operator<<(std::ostream &os, Encoding e) {
  switch (e) {
  case Encoding::PLAIN:
    return os << "PLAIN";
  case Encoding::HYBRID:
    return os << "HYBRID";
  default:
    return os << "UNEXPECTED ENCODING";
  }
}

std::ostream &operator<<(std::ostream &os, Compression c) {
  switch (c) {
  case Compression::RAW:
    return os << "RAW";
  case Compression::SNAPPY:
    return os << "SNAPPY";
  default:
    return os << "UNEXPECTED COMPRESSION";
  }
}

static void read_exact(std::istream &is, void *dst, size_t n) {
  if (!is.read(reinterpret_cast<char *>(dst), n))
    throw std::runtime_error("unexpected EOF");
}

template <typename Enum> static void read_enum(std::istream &is, Enum *dst) {
  static_assert(sizeof(Enum) == 1, "Enum must be 1 byte");
  uint8_t val = 123;
  if (!is.read(reinterpret_cast<char *>(&val), 1))
    throw std::runtime_error("unexpected EOF reading enum");

  *dst = static_cast<Enum>(val);
}

std::string read_string(std::istream &is) {
  uint32_t n;
  read_exact(is, &n, sizeof(uint32_t));

  std::string str(n, '\0');
  read_exact(is, str.data(), n);
  return str;
}

Page Page::from(std::istream &is) {
  Page p;
  read_enum(is, &p.encoding);
  read_exact(is, &p.offset, sizeof(p.offset));
  read_exact(is, &p.size, sizeof(p.size));
  read_exact(is, &p.num_values, sizeof(p.num_values));
  return p;
}

ColumnChunk ColumnChunk::from(std::istream &is) {
  ColumnChunk c;
  uint32_t n;

  read_enum(is, &c.type);
  read_exact(is, &c.num_values, sizeof(c.num_values));
  read_exact(is, &c.hybrid_num_values, sizeof(c.hybrid_num_values));
  read_enum(is, &c.compression);

  bool has_dict;
  read_exact(is, &has_dict, sizeof(has_dict));
  if (has_dict)
    c.dictionary = Page::from(is);

  read_exact(is, &n, sizeof(uint32_t));
  c.data.reserve(n);
  for (uint32_t i = 0; i < n; ++i)
    c.data.push_back(Page::from(is));

  return c;
}

RowGroup RowGroup::from(std::istream &is) {
  RowGroup g;
  uint32_t n;
  read_exact(is, &n, sizeof(uint32_t));
  g.chunks.reserve(n);
  for (uint32_t i = 0; i < n; ++i)
    g.chunks.push_back(ColumnChunk::from(is));
  return g;
}

Metadata Metadata::from(std::istream &is) {
  Metadata m;
  uint32_t n;

  read_exact(is, &n, sizeof(uint32_t));
  m.column_names.reserve(n);
  for (uint32_t i = 0; i < n; ++i)
    m.column_names.push_back(read_string(is));

  read_exact(is, &n, sizeof(uint32_t));
  m.groups.reserve(n);
  for (uint32_t i = 0; i < n; ++i)
    m.groups.push_back(RowGroup::from(is));
  return m;
}

} // namespace metadata
} // namespace parcore
