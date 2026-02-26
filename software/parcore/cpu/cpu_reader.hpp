#pragma once

#include <queue>

#include <parquet/arrow/reader.h>

#include <parcore/reader.hpp>

namespace parcore {
namespace cpu {

class CPUReader : public Reader {
private:
  std::unique_ptr<parquet::arrow::FileReader> file_reader_;
  std::queue<std::shared_ptr<parquet::arrow::ColumnChunkReader>> queue_;

public:
  CPUReader(std::shared_ptr<arrow::io::RandomAccessFile> file);

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] bool has_next_column_chunk() override;

  [[nodiscard]] std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk() override;
};

} // namespace cpu
} // namespace parcore
