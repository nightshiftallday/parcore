#include <parcore/metadata/metadata.hpp>

#include <iostream>
#include <ostream>
#include <stdexcept>

namespace parcore {
namespace metadata {

std::ostream &operator<<(std::ostream &os, Encoding e) {
  switch (e) {
  case Encoding::PLAIN:
    return os << "PLAIN";
  case Encoding::HYBRID:
    return os << "HYBRID";
  default:
    throw std::runtime_error("unexpected encoding");
  }
}

std::ostream &operator<<(std::ostream &os, Compression c) {
  switch (c) {
  case Compression::RAW:
    return os << "RAW";
  case Compression::SNAPPY:
    return os << "SNAPPY";
  default:
    throw std::runtime_error("unexpected compression");
  }
}

std::ostream &operator<<(std::ostream &os, Type t) {
  switch (t) {
  case Type::BYTE:
    return os << "BYTE";
  case Type::INT32:
    return os << "INT32";
  case Type::INT64:
    return os << "INT64";
  case Type::FLOAT:
    return os << "FLOAT";
  case Type::DOUBLE:
    return os << "DOUBLE";
  default:
    throw std::runtime_error("unexpected type");
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

Page Page::from(std::istream &is) {
  Page p;
  read_enum(is, &p.encoding);
  read_exact(is, &p.offset, sizeof(p.offset));
  read_exact(is, &p.size, sizeof(p.size));
  return p;
}

ColumnChunk ColumnChunk::from(std::istream &is) {
  ColumnChunk c;
  read_enum(is, &c.type);
  read_exact(is, &c.num_values, sizeof(c.num_values));
  read_enum(is, &c.compression);

  bool has_dict;
  read_exact(is, &has_dict, sizeof(has_dict));
  if (has_dict)
    c.dictionary = Page::from(is);

  c.data = Page::from(is);
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
  m.groups.reserve(n);
  for (uint32_t i = 0; i < n; ++i)
    m.groups.push_back(RowGroup::from(is));
  return m;
}

} // namespace metadata
} // namespace parcore
