#pragma once

#include <arrow/io/file.h>

#include <parcore/fpga/reader.hpp>

namespace parcore {

namespace fpga {

/*
 * This reader preloads all pages in memory to avoid any overhead when measuring
 * performance of the decoder.
 */
class PreloadFileReader : public HardwareReader {
private:
  std::unordered_map<metadata::Page, std::shared_ptr<libstf::Buffer>> pages_;

public:
  PreloadFileReader(
      std::shared_ptr<coyote::cThread> cthread,
      std::shared_ptr<libstf::MemoryPool> memory_pool,
      std::shared_ptr<libstf::TLBManager> tlb_manager,
      std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
      std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
      std::shared_ptr<PageDecoderConfig> page_config,
      const metadata::Metadata &meta,
      std::shared_ptr<arrow::io::RandomAccessFile> file,
      libstf::stream_t decoder = 0);

protected:
  std::shared_ptr<libstf::Buffer>
  load_page(std::shared_ptr<arrow::io::RandomAccessFile> file,
            const metadata::Page &page);

  void send_page(const metadata::Page &page, PageType page_type) override;
};

} // namespace fpga

} // namespace parcore
