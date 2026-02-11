#pragma once

#include <fstream>
#include <memory>

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

protected:
  void send_page(const metadata::Page &page, PageType page_type);
};

} // namespace parcore
