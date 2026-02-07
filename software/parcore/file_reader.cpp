#include <stdexcept>

#include <libstf/profiling.hpp>
#include <parcore/file_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>

using libstf::profiler;

namespace parcore {

FileReader::FileReader(std::shared_ptr<coyote::cThread> cthread,
                       std::shared_ptr<libstf::MemoryPool> pool,
                       std::shared_ptr<libstf::TLBManager> tlb,
                       PageDecoderConfig config, const metadata::Metadata &meta,
                       std::ifstream file, uint32_t stream)
    : Reader(cthread, pool, tlb, config, meta, nullptr, stream),
      file(std::move(file)) {}

FileReader::FileReader(std::shared_ptr<coyote::cThread> cthread,
                       std::shared_ptr<libstf::MemoryPool> pool,
                       std::shared_ptr<libstf::TLBManager> tlb,
                       PageDecoderConfig config, std::string path,
                       uint32_t stream)
    : Reader(cthread, pool, tlb, config, metadata::from_file(path + ".meta"),
             nullptr, stream),
      file(path) {}

void FileReader::send_page(const metadata::ColumnChunk &chunk,
                           const metadata::Page &page, PageType page_type) {
  profiler::open_regions({"send_page"});

  auto buffer = allocate_buffer(page.size);

  profiler::open_regions({"read_page"});
  if (file.seekg(page.offset).fail()) {
    throw std::runtime_error("error while seeking to page");
  }

  if (file.read(static_cast<char *>(buffer->ptr), page.size).fail()) {
    throw std::runtime_error("error while reading page");
  }
  profiler::close_regions({"read_page"});

  enqueue_stream_input(*buffer.get());

  profiler::close_regions({"send_page"});
}

} // namespace parcore
