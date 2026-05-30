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

std::vector<std::shared_ptr<libstf::Buffer>> MemoryReader::next_column_chunk() {
  auto result = HardwareReader::next_column_chunk();
  assert(!buffers_.empty());
  buffers_.pop_front();
  return result;
}

std::shared_ptr<libstf::Buffer>
MemoryReader::get_chunk_data(const metadata::ColumnChunk &column_chunk) {
  Profiler::open_regions({prefix + "get_chunk_data"});

  // TODO: remove this memcpy when Coyote supports unaligned address transfers.
  auto buffer = allocate_buffer(column_chunk.total_compressed_size);

  auto byte_ptr = static_cast<const std::byte *>(data_->ptr);
  std::memcpy(buffer->ptr, byte_ptr + column_chunk.offset,
              column_chunk.total_compressed_size);

  buffers_.push_back(buffer);

  Profiler::close_regions({prefix + "get_chunk_data"});
  return buffer;
}

} // namespace parcore
