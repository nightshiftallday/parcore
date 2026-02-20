#include <libstf/profiling.hpp>
#include <parcore/memory_reader.hpp>

using libstf::Profiler;

namespace parcore {

MemoryReader::MemoryReader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    ColumnChunkDecoderConfig column_chunk_config, PageDecoderConfig page_config,
    const metadata::Metadata &meta, std::shared_ptr<libstf::Buffer> data,
    libstf::stream_t decoder)
    : Reader(cthread, memory_pool, tlb_manager, output_buffer_manager,
             column_chunk_config, page_config, meta, decoder),
      data_(std::move(data)) {}

const std::string memory_reader_prefix = "parcore::MemoryReader::";

void MemoryReader::send_page(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({memory_reader_prefix + "send_page"});
  auto byte_ptr = static_cast<const std::byte *>(data_->ptr);

  auto buffer = libstf::Buffer{
      .ptr = const_cast<void *>(
          reinterpret_cast<const void *>(byte_ptr + page.offset)),
      .size = page.size,
      .capacity = data_->capacity - page.offset,
  };

  enqueue_stream_input(buffer);

  Profiler::close_regions({memory_reader_prefix + "send_page"});
}

} // namespace parcore
