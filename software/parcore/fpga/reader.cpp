#include <cstring>

#include <coyote/cThread.hpp>
#include <libstf/profiling.hpp>
#include <parcore/configuration.hpp>
#include <parcore/fpga/reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>

using libstf::Profiler;

namespace parcore {

namespace fpga {

const std::string reader_prefix = "parcore::Reader::";

void HardwareReader::enqueue_stream_input(const libstf::Buffer &buffer) {
  Profiler::open_regions({reader_prefix + "enqueue_stream_input"});
  auto byte_ptr = static_cast<const std::byte *>(buffer.ptr);
  tlb_manager_->ensure_tlb_mapping(buffer.ptr, buffer.capacity);

  for (size_t off = 0; off < buffer.size; off += coyote::MAX_TRANSFER_SIZE) {
    // Get the address and output_size of this chunk
    auto curr_ptr = (void *)(byte_ptr + off);
    auto input_size = std::min(buffer.size - off, coyote::MAX_TRANSFER_SIZE);

    // Configure the data transfer
    coyote::localSg sg;
    sg.addr = curr_ptr;
    sg.len = input_size;
    sg.stream = coyote::STRM_HOST;
    sg.dest = decoder_;

    auto last_transfer = off + coyote::MAX_TRANSFER_SIZE >= buffer.size;
    Profiler::open_regions({reader_prefix + "local_read"});
    auto start = std::chrono::high_resolution_clock::now();
    cthread_->invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
    auto end = std::chrono::high_resolution_clock::now();
    auto us = std::chrono::duration_cast<std::chrono::microseconds>(end - start)
                  .count();
    Profiler::close_regions({reader_prefix + "local_read"});
  }
  Profiler::close_regions({reader_prefix + "enqueue_stream_input"});
}

HardwareReader::HardwareReader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
    std::shared_ptr<PageDecoderConfig> page_config,
    const metadata::Metadata &meta, libstf::stream_t decoder)
    : cthread_(cthread), memory_pool_(memory_pool), tlb_manager_(tlb_manager),
      output_buffer_manager_(output_buffer_manager),
      column_chunk_config_(column_chunk_config), page_config_(page_config),
      meta_(meta), decoder_(decoder) {

  assert(cthread_ != nullptr);
  assert(memory_pool_ != nullptr);
  assert(tlb_manager_ != nullptr);
  assert(output_buffer_manager_ != nullptr);
}

std::shared_ptr<libstf::Buffer> HardwareReader::allocate_buffer(size_t size) {
  void *ptr;
  auto status = memory_pool_->allocate(size, reinterpret_cast<void **>(&ptr));
  if (!status.ok()) {
    throw std::runtime_error("could not allocate memory: " + status.message());
  }

  auto buffer(libstf::make_buffer(memory_pool_, ptr, size, size));
  tlb_manager_->ensure_tlb_mapping(buffer->ptr, buffer->size);

  return std::move(buffer);
}

libstf::stream_mask_t HardwareReader::decoder_mask() const {
  libstf::stream_mask_t mask;
  mask.set(decoder_);
  return mask;
}

const metadata::Metadata &HardwareReader::metadata() const { return meta_; }
const libstf::stream_t &HardwareReader::decoder() const { return decoder_; }

std::shared_ptr<libstf::OutputHandle>
HardwareReader::decode_column_chunk(size_t chunk, size_t column) {
  Profiler::open_regions({reader_prefix + "enqueue_column_chunk"});

  auto column_chunk = get_column_chunk(meta_, chunk, column);

  // std::cout << "starting initial configuration" << std::endl;
  // auto start = std::chrono::high_resolution_clock::now();
  auto type = metadata::to_libstf_type(column_chunk.type);
  column_chunk_config_->process_column_chunk(
      decoder_, column_chunk.compression, column_chunk.num_values,
      column_chunk.hybrid_num_values, type);

  // Storing the result handle in the queue
  auto output_handle =
      output_buffer_manager_->acquire_output_handle(decoder_mask());

  // Confiure the decoding for all pages before hand.
  if (column_chunk.dictionary != std::nullopt) {
    page_config_->process_page(decoder_, PageType::DICT,
                               column_chunk.dictionary->encoding, 0, false);
  }
  size_t i = 0;
  for (auto page : column_chunk.data) {
    bool last = i == column_chunk.data.size() - 1;
    page_config_->process_page(decoder_, PageType::DATA, page.encoding,
                               page.num_values, last);
    ++i;
  }
  // auto end = std::chrono::high_resolution_clock::now();
  // auto us = std::chrono::duration_cast<std::chrono::microseconds>(end -
  // start)
  //               .count();
  // std::cout << "initial configuration done, took " << us << "us" <<
  // std::endl;

  // std::cout << "starting data sending" << std::endl;
  // start = std::chrono::high_resolution_clock::now();
  if (column_chunk.dictionary != std::nullopt) {
    send_page(*column_chunk.dictionary, PageType::DICT);
  }
  for (auto page : column_chunk.data) {
    send_page(page, PageType::DATA);
  }
  // end = std::chrono::high_resolution_clock::now();
  // us = std::chrono::duration_cast<std::chrono::microseconds>(end - start)
  //          .count();
  // std::cout << "sending data done, took " << us << "us" << std::endl;

  Profiler::close_regions({reader_prefix + "enqueue_column_chunk"});
  return std::move(output_handle);
}

} // namespace fpga

} // namespace parcore
