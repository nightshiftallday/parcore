#include <libstf/profiling.hpp>
#include <parcore/memory_reader.hpp>

using libstf::Profiler;

namespace parcore {

MemoryReader::MemoryReader(
    std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    const metadata::Metadata &meta, std::shared_ptr<libstf::Buffer> data)
    : HardwareReader(std::move(column_chunk_decoder), std::move(memory_pool),
                     meta),
      data_(std::move(data)) {}

const std::string prefix = "parcore::MemoryReader::";

void MemoryReader::enqueue_column_chunk(size_t chunk, size_t column) {
  // Add a new entry to the queue of buffers used in each request
  buffers_.push_back(std::vector<std::shared_ptr<libstf::Buffer>>());

  HardwareReader::enqueue_column_chunk(chunk, column);
}

std::vector<std::shared_ptr<libstf::Buffer>> MemoryReader::next_column_chunk() {
  auto result = HardwareReader::next_column_chunk();
  buffers_.pop_front(); // drop the buffers that were kept alive until the
                        // result is returned from the FPGA
  return result;
}

std::shared_ptr<libstf::Buffer>
MemoryReader::get_page_data(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({prefix + "get_page_data"});

  // TODO: remove this memcpy and all the logic to keep the buffer alive when we
  // can just take an offset in to the buffer that's already in memory and send
  // that through Coyote.
  //
  // Currently that's not possible due to a malformed keep when memory starting
  // from an unaligned address.
  auto buffer = allocate_buffer(page.size);

  auto byte_ptr = static_cast<const std::byte *>(data_->ptr);
  std::memcpy(buffer->ptr, byte_ptr + page.offset, page.size);

  // Store the reference to the buffer in the queue so it won't be freed until
  // we have compltely parsed the column chunk that this page belongs to.
  assert(!buffers_.empty());
  buffers_.back().push_back(buffer);

  Profiler::close_regions({prefix + "get_page_data"});
  return buffer;
}

} // namespace parcore
