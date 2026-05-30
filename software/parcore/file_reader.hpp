#pragma once

#include <arrow/io/file.h>

#include <parcore/hardware_reader.hpp>

namespace parcore {

class FileReader : public HardwareReader {
public:
  FileReader(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
             std::shared_ptr<libstf::MemoryPool> memory_pool,
             const metadata::Metadata &meta,
             std::shared_ptr<arrow::io::RandomAccessFile> file);

  [[nodiscard]] std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk() override;

protected:
  std::shared_ptr<libstf::Buffer>
  get_chunk_data(const metadata::ColumnChunk &column_chunk) override;

private:
  std::shared_ptr<arrow::io::RandomAccessFile> file_;
  std::deque<std::shared_ptr<libstf::Buffer>> buffers_;
};

} // namespace parcore
