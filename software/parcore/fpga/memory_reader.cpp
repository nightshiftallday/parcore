#include <libstf/profiling.hpp>
#include <parcore/fpga/memory_reader.hpp>

using libstf::Profiler;

namespace parcore {

namespace fpga {

MemoryReader::MemoryReader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
    std::shared_ptr<PageDecoderConfig> page_config,
    const metadata::Metadata &meta, std::shared_ptr<libstf::Buffer> data,
    libstf::stream_t decoder)
    : HardwareReader(cthread, memory_pool, tlb_manager, output_buffer_manager,
                     column_chunk_config, page_config, meta, decoder),
      data_(std::move(data)) {}

const std::string prefix = "parcore::MemoryReader::";

std::shared_ptr<libstf::OutputHandle>
MemoryReader::decode_column_chunk(size_t chunk, size_t column) {
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

void MemoryReader::send_page(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({prefix + "send_page"});

  std::cout << "copying memory" << std::endl;
  auto start = std::chrono::high_resolution_clock::now();
  // TODO: remove this memcpy and all the logic to keep the buffer alive when we
  // can just take an offset in to the buffer that's already in memory and send
  // that through Coyote.
  //
  // Currently that's not possible due to a malformed keep when memory starting
  // from an unaligned address.
  auto buffer = allocate_buffer(page.size);

  assert(buffers_per_column_chunk_.contains(decode_id_));
  buffers_per_column_chunk_[decode_id_].push_back(buffer);

  auto byte_ptr = static_cast<const std::byte *>(data_->ptr);
  std::memcpy(buffer->ptr, byte_ptr + page.offset, page.size);

  auto end = std::chrono::high_resolution_clock::now();
  auto us = std::chrono::duration_cast<std::chrono::microseconds>(end - start)
                .count();
  std::cout << "memory copied, took " << us << "us" << std::endl;

  enqueue_stream_input(*buffer.get());

  Profiler::close_regions({prefix + "send_page"});
}

} // namespace fpga

} // namespace parcore
