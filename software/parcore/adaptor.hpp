#pragma once

#include <arrow/array.h>
#include <arrow/buffer.h>
#include <arrow/chunked_array.h>

#include <libstf/buffer.hpp>
#include <memory>
#include <parcore/file_reader.hpp>
#include <parcore/memory_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/preload_file_reader.hpp>
#include <parcore/reader.hpp>
#include <queue>

namespace parcore {

class Buffer : public arrow::Buffer {
public:
  /**
   * Creates a new instance of an Arrow Buffer referencing some libstf::Buffer
   * memory.
   *
   * @param buf A shared pointer to the libstf::Buffer.
   */
  Buffer(std::shared_ptr<libstf::Buffer> buf);

private:
  std::shared_ptr<libstf::Buffer> buf_;
};

std::shared_ptr<arrow::ChunkedArray> libstf_buffers_into_arrow(
    std::vector<std::shared_ptr<libstf::Buffer>> output_handle,
    size_t num_values, metadata::Type type);

template <typename HWReader> class Adaptor : public Reader {
public:
  template <typename... Args>
  explicit Adaptor(Args &&...args) : hw_(std::forward<Args>(args)...) {}

  const metadata::Metadata &metadata() const override { return hw_.metadata(); }

  void enqueue_column_chunk(size_t chunk, size_t column) override {
    auto column_chunk = metadata::get_column_chunk(metadata(), chunk, column);

    auto handle = Handle{
        .num_values = column_chunk.num_values,
        .type = column_chunk.type,
    };

    hw_.enqueue_column_chunk(chunk, column);
    handle_queue_.push(handle);
  }

  bool has_next_column_chunk() override { return hw_.has_next_column_chunk(); }

  std::shared_ptr<arrow::ChunkedArray> next_column_chunk() override {
    auto buffers = hw_.next_column_chunk();

    assert(!handle_queue_.empty());
    auto handle = handle_queue_.front();
    handle_queue_.pop();

    return libstf_buffers_into_arrow(buffers, handle.num_values, handle.type);
  }

private:
  struct Handle {
    size_t num_values;
    metadata::Type type;
  };

  HWReader hw_;
  std::queue<Handle> handle_queue_;
};

template <typename HWReader, typename... Args>
std::shared_ptr<Reader> make_hardware_adaptor(Args &&...args) {
  return std::make_shared<Adaptor<HWReader>>(std::forward<Args>(args)...);
}

namespace adapted {

using FileReader = Adaptor<FileReader>;
using PreloadFileReader = Adaptor<PreloadFileReader>;
using MemoryReader = Adaptor<MemoryReader>;

} // namespace adapted

} // namespace parcore
