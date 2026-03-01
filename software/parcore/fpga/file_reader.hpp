#pragma once

#include <arrow/io/file.h>

#include <parcore/fpga/reader.hpp>
#include <unordered_map>

namespace parcore {

namespace fpga {

class FileReader : public HardwareReader {
private:
  std::shared_ptr<arrow::io::RandomAccessFile> file_;
  size_t decode_id_;
  std::unordered_map<size_t, std::vector<std::shared_ptr<libstf::Buffer>>>
      buffers_per_column_chunk_;

public:
  FileReader(std::shared_ptr<coyote::cThread> cthread,
             std::shared_ptr<libstf::MemoryPool> memory_pool,
             std::shared_ptr<libstf::TLBManager> tlb_manager,
             std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
             std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
             std::shared_ptr<PageDecoderConfig> page_config,
             const metadata::Metadata &meta,
             std::shared_ptr<arrow::io::RandomAccessFile> file,
             libstf::stream_t decoder = 0);

  [[nodiscard]] std::shared_ptr<libstf::OutputHandle>
  decode_column_chunk(size_t chunk, size_t column) override;

protected:
  void send_page(const metadata::Page &page, PageType page_type) override;
};

} // namespace fpga

} // namespace parcore
