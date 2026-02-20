#include <stdexcept>

#include <libstf/profiling.hpp>
#include <parcore/file_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>

using libstf::Profiler;

namespace parcore {

FileReader::FileReader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    ColumnChunkDecoderConfig column_chunk_config, PageDecoderConfig page_config,
    const metadata::Metadata &meta, std::ifstream file,
    libstf::stream_t decoder)
    : Reader(cthread, memory_pool, tlb_manager, output_buffer_manager,
             column_chunk_config, page_config, meta, decoder),
      file_(std::move(file)) {}

FileReader::FileReader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    ColumnChunkDecoderConfig column_chunk_config, PageDecoderConfig page_config,
    std::string path, libstf::stream_t decoder)
    : Reader(cthread, memory_pool, tlb_manager, output_buffer_manager,
             column_chunk_config, page_config,
             metadata::from_file(path + ".meta"), decoder),
      file_(path) {}

const std::string file_reader_prefix = "parcore::FileReader::";

// Since the FileReader dynamically allocates memory for each page on demand,
// and the LOCAL_READS to the FPGA are not checked for completion, we must
// ensure ourselves that the memory is not freed. We can acheive this by keeping
// a reference to all the libstf::Buffers used for each request, and dropping
// those references only once the `next_column_chunk` terminates. At that point,
// all buffers must have been consumed since we were able to produce the
// expected number of decoded bytes as a result.

void FileReader::enqueue_column_chunk(size_t chunk, size_t column) {
  // Add a new entry to the queue of buffers used in each request
  buffers_per_column_chunk_.push(
      std::vector<std::shared_ptr<libstf::Buffer>>());

  Reader::enqueue_column_chunk(chunk, column);
}

std::shared_ptr<libstf::Buffer> FileReader::next_column_chunk() {
  auto result = Reader::next_column_chunk();

  // At this point it is safe to free the input buffers, so we pop the vector
  // containing all references.
  assert(buffers_per_column_chunk_.size() > 0);
  buffers_per_column_chunk_.pop();

  return result;
}

void FileReader::send_page(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({file_reader_prefix + "send_page"});

  auto buffer = allocate_buffer(page.size);

  // Store the reference to the buffer in the queue so it won't be freed until
  // we have compltely parsed the column chunk that this page belongs to.
  assert(buffers_per_column_chunk_.size() > 0);
  buffers_per_column_chunk_.front().push_back(buffer);

  Profiler::open_regions({file_reader_prefix + "read_file"});
  if (file_.seekg(page.offset).fail()) {
    throw std::runtime_error("error while seeking to page");
  }

  if (file_.read(static_cast<char *>(buffer->ptr), page.size).fail()) {
    throw std::runtime_error("error while reading page");
  }
  Profiler::close_regions({file_reader_prefix + "read_file"});

  enqueue_stream_input(*buffer.get());

  Profiler::close_regions({file_reader_prefix + "send_page"});
}

} // namespace parcore
