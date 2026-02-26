#pragma once

#include <arrow/io/file.h>
#include <parquet/file_reader.h>

#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>
#include <queue>

namespace parcore {

class HybridReader : public Reader {
public:
  HybridReader(std::shared_ptr<Reader> reader,
               std::shared_ptr<arrow::io::RandomAccessFile> file);

  [[nodiscard]] const metadata::Metadata &metadata() const override;

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] bool has_next_column_chunk() override;

  [[nodiscard]] std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk() override;

private:
  std::shared_ptr<Reader> reader_;
  std::shared_ptr<arrow::io::RandomAccessFile> file_;
  std::unique_ptr<parquet::arrow::FileReader> file_reader_;

private:
  enum class Decoder { HARDWARE, CPU };

  std::queue<Decoder> chosen_decoder_;
};

} // namespace parcore
