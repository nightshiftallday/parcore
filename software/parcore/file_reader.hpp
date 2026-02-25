#pragma once

#include <fstream>
#include <memory>

#include <parcore/reader.hpp>

namespace parcore {

class FileReader : public Reader {
private:
  std::ifstream file_;
  std::queue<std::vector<std::shared_ptr<libstf::Buffer>>>
      buffers_per_column_chunk_;

public:
  FileReader(std::shared_ptr<coyote::cThread> cthread,
             std::shared_ptr<libstf::MemoryPool> memory_pool,
             std::shared_ptr<libstf::TLBManager> tlb_manager,
             std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
             ColumnChunkDecoderConfig column_chunk_config,
             PageDecoderConfig page_config, const metadata::Metadata &meta,
             std::ifstream file, libstf::stream_t decoder = 0);

  FileReader(std::shared_ptr<coyote::cThread> cthread,
             std::shared_ptr<libstf::MemoryPool> memory_pool,
             std::shared_ptr<libstf::TLBManager> tlb_manager,
             std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
             ColumnChunkDecoderConfig column_chunk_config,
             PageDecoderConfig page_config, std::string path,
             libstf::stream_t decoder = 0);

  void enqueue_column_chunk(size_t chunk, size_t column);

  std::vector<std::shared_ptr<libstf::Buffer>> next_column_chunk();

protected:
  void send_page(const metadata::Page &page, PageType page_type);
};

} // namespace parcore
