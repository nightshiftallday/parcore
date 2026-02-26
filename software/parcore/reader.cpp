#include <parcore/reader.hpp>

namespace parcore {

const metadata::ColumnChunk get_column_chunk(const metadata::Metadata &meta,
                                             size_t chunk, size_t column) {
  if (chunk >= meta.groups.size()) {
    throw std::runtime_error("attempted to parse chunk which is out of bounds");
  }
  auto group = meta.groups[chunk];

  if (column >= group.chunks.size()) {
    throw std::runtime_error(
        "attempted to parse column chunk which is out of bounds");
  }

  return group.chunks[column];
}

} // namespace parcore
