#pragma once

#include <fstream>
#include <memory>
#include <queue>

#include <coyote/cThread.hpp>
#include <libstf/buffer.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/tlb_manager.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>

namespace parcore {

class FileReader : public Reader {
private:
  std::ifstream file;

public:
  FileReader(std::shared_ptr<coyote::cThread> cthread,
             std::shared_ptr<libstf::MemoryPool> pool,
             std::shared_ptr<libstf::TLBManager> tlb, PageDecoderConfig config,
             const metadata::Metadata &meta, std::ifstream file,
             libstf::stream_t stream = 0);

  FileReader(std::shared_ptr<coyote::cThread> cthread,
             std::shared_ptr<libstf::MemoryPool> pool,
             std::shared_ptr<libstf::TLBManager> tlb, PageDecoderConfig config,
             std::string path, libstf::stream_t stream = 0);

private:
  void send_page(const metadata::ColumnChunk &column_chunk,
                 const metadata::Page &page, PageType page_type);
};

} // namespace parcore
