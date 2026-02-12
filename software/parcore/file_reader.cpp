#include <stdexcept>

#include <libstf/profiling.hpp>
#include <parcore/file_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>

using libstf::Profiler;

namespace parcore {

FileReader::FileReader(std::shared_ptr<coyote::cThread> cthread,
                       std::shared_ptr<libstf::MemoryPool> pool,
                       std::shared_ptr<libstf::TLBManager> tlb,
                       PageDecoderConfig config, const metadata::Metadata &meta,
                       std::ifstream file, libstf::stream_t stream)
    : Reader(cthread, pool, tlb, config, meta, nullptr, stream),
      file(std::move(file)) {}

FileReader::FileReader(std::shared_ptr<coyote::cThread> cthread,
                       std::shared_ptr<libstf::MemoryPool> pool,
                       std::shared_ptr<libstf::TLBManager> tlb,
                       PageDecoderConfig config, std::string path,
                       libstf::stream_t stream)
    : Reader(cthread, pool, tlb, config, metadata::from_file(path + ".meta"),
             nullptr, stream),
      file(path) {}

const std::string file_reader_prefix = "parcore::FileReader::";

void FileReader::send_page(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({file_reader_prefix + "send_page"});

  auto buffer = allocate_buffer(page.size);

  Profiler::open_regions({file_reader_prefix + "read_file"});
  if (file.seekg(page.offset).fail()) {
    throw std::runtime_error("error while seeking to page");
  }

  if (file.read(static_cast<char *>(buffer->ptr), page.size).fail()) {
    throw std::runtime_error("error while reading page");
  }
  Profiler::close_regions({file_reader_prefix + "read_file"});

  enqueue_stream_input(*buffer.get());

  Profiler::close_regions({file_reader_prefix + "send_page"});
}

} // namespace parcore
