#include "preload_file_reader.hpp"
#include <libstf/profiling.hpp>
#include <optional>
#include <parcore/fpga/preload_file_reader.hpp>

using libstf::Profiler;

namespace parcore {

namespace fpga {

PreloadFileReader::PreloadFileReader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
    std::shared_ptr<PageDecoderConfig> page_config,
    const metadata::Metadata &meta,
    std::shared_ptr<arrow::io::RandomAccessFile> file, libstf::stream_t decoder)
    : HardwareReader(cthread, memory_pool, tlb_manager, output_buffer_manager,
                     column_chunk_config, page_config, meta, decoder) {
  for (auto row_group : meta_.groups) {
    for (auto column_chunk : row_group.chunks) {
      if (column_chunk.dictionary != std::nullopt) {
        auto page = *column_chunk.dictionary;
        pages_.insert({page, load_page(file, page)});
      }

      for (auto page : column_chunk.data) {
        pages_.insert({page, load_page(file, page)});
      }
    }
  }
}

const std::string prefix = "parcore::PreloadFileReader::";

std::shared_ptr<libstf::Buffer>
PreloadFileReader::load_page(std::shared_ptr<arrow::io::RandomAccessFile> file,
                             const metadata::Page &page) {
  Profiler::open_regions({prefix + "load_page"});

  auto buffer = allocate_buffer(page.size);

  auto seek_status = file->Seek(page.offset);
  if (!seek_status.ok())
    throw std::runtime_error("error while seeking to page: " +
                             seek_status.message());
  auto read_status = file->Read(page.size, buffer->ptr);
  if (!read_status.ok())
    throw std::runtime_error("error while reading page: " +
                             read_status.status().message());
  assert(read_status.ValueOrDie() == page.size);

  Profiler::close_regions({prefix + "load_page"});
  return std::move(buffer);
}

void PreloadFileReader::send_page(const metadata::Page &page,
                                  PageType page_type) {
  Profiler::open_regions({prefix + "send_page"});

  auto buffer = pages_[page];
  enqueue_stream_input(*buffer.get());

  Profiler::close_regions({prefix + "send_page"});
}

} // namespace fpga

} // namespace parcore
