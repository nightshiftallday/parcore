#pragma once

#include <queue>
#include <thread>

#include <parquet/arrow/reader.h>

#include <parcore/reader.hpp>

namespace parcore {

namespace cpu {

class CPUReader : public Reader {
private:
  struct Job {
    std::shared_ptr<parquet::arrow::ColumnChunkReader> reader;
    std::shared_ptr<arrow::ChunkedArray> out;
  };
  static inline void read_column_chunk(CPUReader::Job *);

  std::unique_ptr<parquet::arrow::FileReader> file_reader_;
  std::queue<std::pair<std::thread, Job *>> queue_;

public:
  CPUReader(std::shared_ptr<arrow::io::RandomAccessFile> file,
            arrow::MemoryPool *memory_pool = nullptr, bool use_threads = false);

  [[nodiscard]] const metadata::Metadata &metadata() const override;

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] bool has_next_column_chunk() override;

  [[nodiscard]] std::shared_ptr<arrow::ChunkedArray>
  next_column_chunk() override;
};

} // namespace cpu

} // namespace parcore
