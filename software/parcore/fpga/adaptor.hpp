#pragma once

#include <arrow/array.h>
#include <arrow/chunked_array.h>

#include <libstf/buffer.hpp>
#include <memory>
#include <parcore/fpga/buffer.hpp>
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
  explicit Adaptor(Args &&...args) : hw_(std::forward<Args>(args)...) {}

  const metadata::Metadata &metadata() const override { return hw_.metadata(); }

  void enqueue_column_chunk(size_t chunk, size_t column) override {
    hw_.enqueue_column_chunk(chunk, column);

    auto column_chunk = get_column_chunk(hw_.metadata(), chunk, column);
    auto result_metadata = ResultMetadata{
        .num_values = column_chunk.num_values,
        .type = column_chunk.type,
    };
    queue_.push(result_metadata);
  }

  bool has_next_column_chunk() override { return hw_.has_next_column_chunk(); }

  std::shared_ptr<arrow::ChunkedArray> next_column_chunk() override {
    assert(!queue_.empty());

    auto result_metadata = queue_.front();
    queue_.pop();

    auto buffers = hw_.next_column_chunk();

    std::vector<std::shared_ptr<arrow::Array>> chunks;
    chunks.reserve(buffers.size());

    for (auto &buf : buffers) {
      auto wrapper = std::make_shared<Buffer>(std::move(buf));

      auto type = metadata::to_arrow_type(result_metadata.type);
      auto num_values = result_metadata.num_values;

      auto array_data =
          arrow::ArrayData::Make(type, num_values, {nullptr, wrapper});
      auto array = arrow::MakeArray(array_data);
      chunks.push_back(array);
    }

    return std::make_shared<arrow::ChunkedArray>(std::move(chunks));
  }

private:
  struct ResultMetadata {
    size_t num_values;
    metadata::Type type;
  };

  HWReader hw_;
  std::queue<ResultMetadata> queue_;
};

template <typename HWReader, typename... Args>
std::shared_ptr<Reader> make_hardware_adaptor(Args &&...args) {
  return std::make_shared<Adaptor<HWReader>>(std::forward<Args>(args)...);
}

namespace adapted {

using FileReader = Adaptor<FileReader>;
using MemoryReader = Adaptor<MemoryReader>;

} // namespace adapted

} // namespace fpga
} // namespace parcore
