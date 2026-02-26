#pragma once

#include <fstream>
#include <memory>

#include <arrow/io/file.h>

#include <parcore/base_reader.hpp>

namespace parcore {

class FileReader : public BaseReader {
private:
  std::shared_ptr<arrow::io::RandomAccessFile> file_;
  std::queue<std::vector<std::shared_ptr<libstf::Buffer>>>
      buffers_per_column_chunk_;

public:
  FileReader(std::shared_ptr<coyote::cThread> cthread,
             std::shared_ptr<libstf::MemoryPool> memory_pool,
             std::shared_ptr<libstf::TLBManager> tlb_manager,
             std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
             ColumnChunkDecoderConfig column_chunk_config,
             PageDecoderConfig page_config, const metadata::Metadata &meta,
             std::shared_ptr<arrow::io::RandomAccessFile> file,
             libstf::stream_t decoder = 0);

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk() override;

protected:
  void send_page(const metadata::Page &page, PageType page_type) override;
};

} // namespace parcore
