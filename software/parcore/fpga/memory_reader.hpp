#pragma once

#include <parcore/fpga/reader.hpp>

namespace parcore {

namespace fpga {

class MemoryReader : public HardwareReader {
private:
  std::shared_ptr<libstf::Buffer> data_;

public:
  MemoryReader(
      std::shared_ptr<coyote::cThread> cthread,
      std::shared_ptr<libstf::MemoryPool> memory_pool,
      std::shared_ptr<libstf::TLBManager> tlb_manager,
      std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
      ColumnChunkDecoderConfig column_chunk_config,
      PageDecoderConfig page_config, const metadata::Metadata &meta,
      std::shared_ptr<libstf::Buffer> data, libstf::stream_t decoder = 0);

protected:
  void send_page(const metadata::Page &page, PageType page_type);
};

} // namespace fpga

} // namespace parcore
