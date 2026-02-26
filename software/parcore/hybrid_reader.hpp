#pragma once

#include <arrow/io/file.h>
#include <parquet/file_reader.h>

#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>
#include <queue>

namespace parcore {

class HybridReader : public Reader {
public:
  HybridReader(std::shared_ptr<Reader> hardware_reader,
               std::shared_ptr<Reader> software_reader);

  [[nodiscard]] const metadata::Metadata &metadata() const override;

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] bool has_next_column_chunk() override;

  [[nodiscard]] std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk() override;

private:
  std::shared_ptr<Reader> hardware_reader_;
  std::shared_ptr<Reader> software_reader_;

private:
  enum class Decoder { HARDWARE, SOFTWARE };

  std::queue<Decoder> chosen_decoder_;
};

} // namespace parcore
