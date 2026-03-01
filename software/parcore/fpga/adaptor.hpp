#pragma once

#include <arrow/array.h>
#include <arrow/chunked_array.h>

#include <libstf/buffer.hpp>
#include <memory>
#include <parcore/fpga/file_reader.hpp>
#include <parcore/fpga/memory_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>
#include <queue>

namespace parcore {

namespace fpga {

template <typename HWReader> class Adaptor : public Reader {
public:
  template <typename... Args>
  explicit Adaptor(Args &&...args)
      : hw_(std::forward<Args>(args)...), decoder_(hw_.decoder()) {}

  const metadata::Metadata &metadata() const override { return hw_.metadata(); }

  void enqueue_column_chunk(size_t chunk, size_t column) override {
    auto handle = hw_.enqueue_column_chunk(chunk, column);

    auto column_chunk = get_column_chunk(hw_.metadata(), chunk, column);
    auto chunk_handle = ChunkHandle{
        .num_values = column_chunk.num_values,
        .type = column_chunk.type,
        .handle = handle,
    };
    queue_.push(chunk_handle);
  }

  bool has_next_column_chunk() override { return !queue_.empty(); }

  std::shared_ptr<arrow::ChunkedArray> next_column_chunk() override {
    assert(!queue_.empty());

    auto chunk_handle = queue_.front();
    queue_.pop();

    auto output_handle = hw_.next_column_chunk();
    return collect_from_output_handle_into_arrow(
        output_handle, decoder_, chunk_handle.type, chunk_handle.num_values);
  }

private:
  struct ChunkHandle {
    size_t num_values;
    metadata::Type type;
    std::shared_ptr<libstf::OutputHandle> handle;
  };

  HWReader hw_;
  libstf::stream_t decoder_;
  std::queue<ChunkHandle> queue_;
};

template <typename HWReader, typename... Args>
std::shared_ptr<Reader> make_hardware_adaptor(Args &&...args) {
  return std::make_shared<Adaptor<HWReader>>(std::forward<Args>(args)...);
}

std::shared_ptr<arrow::ChunkedArray> collect_from_output_handle_into_arrow(
    std::shared_ptr<libstf::OutputHandle> output_handle,
    libstf::stream_t decoder, size_t num_values, metadata::Type type);

namespace adapted {

using FileReader = Adaptor<FileReader>;
using MemoryReader = Adaptor<MemoryReader>;

} // namespace adapted

} // namespace fpga
} // namespace parcore
