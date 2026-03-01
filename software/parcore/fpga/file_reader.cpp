#include <stdexcept>

#include <libstf/profiling.hpp>
#include <parcore/fpga/file_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>

using libstf::Profiler;

namespace parcore {

namespace fpga {

FileReader::FileReader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
    std::shared_ptr<PageDecoderConfig> page_config,
    const metadata::Metadata &meta,
    std::shared_ptr<arrow::io::RandomAccessFile> file, libstf::stream_t decoder)
    : HardwareReader(cthread, memory_pool, tlb_manager, output_buffer_manager,
                     column_chunk_config, page_config, meta, decoder),
      file_(std::move(file)), decode_id_(0) {}

const std::string prefix = "parcore::FileReader::";

// Since the FileReader dynamically allocates memory for each page on demand,
// and the LOCAL_READS to the FPGA are not checked for completion, we must
// ensure ourselves that the memory is not freed. We can acheive this by keeping
// a reference to all the libstf::Buffers used for each request, and dropping
// those references only once the `next_column_chunk` terminates. At that point,
// all buffers must have been consumed since we were able to produce the
// expected number of decoded bytes as a result.

std::shared_ptr<libstf::OutputHandle>
FileReader::decode_column_chunk(size_t chunk, size_t column) {
  // Add a new entry to the queue of buffers used in each request
  auto id = decode_id_;
  auto expected_decoder = decoder();
  buffers_per_column_chunk_.insert(
      {decode_id_, std::vector<std::shared_ptr<libstf::Buffer>>()});

  auto handle = HardwareReader::decode_column_chunk(chunk, column);
  ++this->decode_id_;

  handle->add_callback([this, expected_decoder, id](libstf::stream_t decoder) {
    assert(decoder == expected_decoder);
    this->buffers_per_column_chunk_.erase(id);
  });
  return std::move(handle);
}

void FileReader::send_page(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({prefix + "send_page"});

  auto buffer = allocate_buffer(page.size);

  // Store the reference to the buffer in the queue so it won't be freed until
  // we have compltely parsed the column chunk that this page belongs to.
  assert(buffers_per_column_chunk_.contains(decode_id_));
  buffers_per_column_chunk_[decode_id_].push_back(buffer);

  Profiler::open_regions({prefix + "read_file"});
  auto seek_status = file_->Seek(page.offset);
  if (!seek_status.ok())
    throw std::runtime_error("error while seeking to page: " +
                             seek_status.message());
  auto read_status = file_->Read(page.size, buffer->ptr);
  if (!read_status.ok())
    throw std::runtime_error("error while reading page: " +
                             read_status.status().message());
  assert(read_status.ValueOrDie() == page.size);

  Profiler::close_regions({prefix + "read_file"});

  enqueue_stream_input(*buffer.get());

  Profiler::close_regions({prefix + "send_page"});
}

} // namespace fpga

} // namespace parcore
