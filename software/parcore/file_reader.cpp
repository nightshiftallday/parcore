#include <parcore/reader.hpp>
#include <stdexcept>

#include <libstf/profiling.hpp>
#include <parcore/file_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>

using libstf::Profiler;

namespace parcore {

FileReader::FileReader(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
                       std::shared_ptr<libstf::MemoryPool> memory_pool,
                       const metadata::Metadata &meta,
                       std::shared_ptr<arrow::io::RandomAccessFile> file)
    : HardwareReader(std::move(column_chunk_decoder), std::move(memory_pool),
                     meta),
      file_(std::move(file)) {}

const std::string prefix = "parcore::FileReader::";

// Since the FileReader dynamically allocates memory for each page on demand,
// and the LOCAL_READS to the FPGA are not checked for completion, we must
// ensure ourselves that the memory is not freed. We can acheive this by keeping
// a reference to all the libstf::Buffers used for each request, and dropping
// those references only once the `next_column_chunk` terminates. At that point,
// all buffers must have been consumed since we were able to produce the
// expected number of decoded bytes as a result.

void FileReader::enqueue_column_chunk(size_t chunk, size_t column) {
  // Add a new entry to the queue of buffers used in each request
  auto vec = std::vector<std::shared_ptr<libstf::Buffer>>();
  vec.reserve(num_pages(get_column_chunk(metadata(), chunk, column)));
  buffers_.push_back(vec);

  HardwareReader::enqueue_column_chunk(chunk, column);
}

std::vector<std::shared_ptr<libstf::Buffer>> FileReader::next_column_chunk() {
  auto result = HardwareReader::next_column_chunk();
  assert(buffers_.front().size() > 0);
  buffers_.pop_front(); // drop the buffers that were kept alive until the
                        // result is returned from the FPGA
  return result;
}

std::shared_ptr<libstf::Buffer>
FileReader::get_page_data(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({prefix + "get_page_data"});

  auto buffer = allocate_buffer(page.size);

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

  // Store the reference to the buffer in the queue so it won't be freed until
  // we have compltely parsed the column chunk that this page belongs to.
  assert(!buffers_.empty());
  buffers_.back().push_back(buffer);
  auto &fr = buffers_.back();

  Profiler::close_regions({prefix + "get_page_data"});
  return buffer;
}

} // namespace parcore
