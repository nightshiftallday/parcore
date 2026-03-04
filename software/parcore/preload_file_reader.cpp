#include <libstf/profiling.hpp>
#include <optional>
#include <parcore/preload_file_reader.hpp>

using libstf::Profiler;

namespace parcore {

PreloadFileReader::PreloadFileReader(
    std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    const metadata::Metadata &meta,
    std::shared_ptr<arrow::io::RandomAccessFile> file)
    : HardwareReader(std::move(column_chunk_decoder), std::move(memory_pool),
                     meta) {
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

std::shared_ptr<libstf::Buffer>
PreloadFileReader::get_page_data(const metadata::Page &page,
                                 PageType page_type) {
  assert(pages_.contains(page));
  return pages_[page];
}

} // namespace parcore
