#pragma once

#include <arrow/chunked_array.h>

#include <libstf/buffer.hpp>
#include <memory>
#include <parcore/fpga/buffer.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>

namespace parcore {

namespace fpga {

template <typename HWReader> class Adaptor : public Reader {
public:
  template <typename... Args>
  explicit Adaptor(Args &&...args) : hw_(std::forward<Args>(args)...) {}

  const metadata::Metadata &metadata() const override { return hw_.metadata(); }

  void enqueue_column_chunk(size_t chunk, size_t column) override {
    hw_.enqueue_column_chunk(chunk, column);
  }

  bool has_next_column_chunk() override { return hw_.has_next_column_chunk(); }

  std::shared_ptr<arrow::ChunkedArray> next_column_chunk() override {
    auto buffers = hw_.next_column_chunk();

    std::vector<std::shared_ptr<arrow::Array>> chunks;
    chunks.reserve(buffers.size());

    for (auto &buf : buffers) {
      auto wrapper = std::make_shared<Buffer>(std::move(buf));
      chunks.push_back(wrapper);
    }

    return std::make_shared<arrow::ChunkedArray>(std::move(chunks));
  }

private:
  HWReader hw_;
};

template <typename HWReader, typename... Args>
std::shared_ptr<Reader> make_hardware_adaptor(Args &&...args) {
  return std::make_shared<Adaptor<HWReader>>(std::forward<Args>(args)...);
}

} // namespace fpga
} // namespace parcore
