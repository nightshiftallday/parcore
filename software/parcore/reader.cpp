#include <algorithm>
#include <cstring>
#include <optional>
#include <stdexcept>

#include <coyote/cThread.hpp>
#include <libstf/profiling.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>
#include <parcore/reader.hpp>

using libstf::Profiler;

namespace parcore {

// ColumnChunkOutput::ColumnChunkOutput(metadata::ColumnChunk column_chunk,
//                                      libstf::OutputHandle output_handle)
//     : column_chunk_(column_chunk), output_handle_(output_handle) {}
//
// const metadata::ColumnChunk &ColumnChunkOutput::column_chunk() const {
//   return column_chunk_;
// }
//
// const libstf::OutputHandle &ColumnChunkOutput::output_handle() const {
//   return output_handle_;
// }

const std::string reader_prefix = "parcore::Reader::";

void Reader::enqueue_stream_input(const libstf::Buffer &buffer) {
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

    // std::cout << "sending data at " << std::hex << curr_ptr << " " <<
    // std::dec
    //           << input_size << "..." << std::flush;
    auto last_transfer = off + coyote::MAX_TRANSFER_SIZE >= buffer.size;
    Profiler::open_regions({reader_prefix + "local_read"});
    cthread_->invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
    // std::cout << "done" << std::endl;
    Profiler::close_regions({reader_prefix + "local_read"});
  }
  Profiler::close_regions({reader_prefix + "enqueue_stream_input"});
}

Reader::Reader(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    ColumnChunkDecoderConfig column_chunk_config, PageDecoderConfig page_config,
    const metadata::Metadata &meta, libstf::stream_t decoder)
    : cthread_(cthread), memory_pool_(memory_pool), tlb_manager_(tlb_manager),
      output_buffer_manager_(output_buffer_manager),
      column_chunk_config_(column_chunk_config), page_config_(page_config),
      meta_(meta), decoder_(decoder) {}

std::shared_ptr<libstf::Buffer> Reader::allocate_buffer(size_t size) {
  void *ptr;
  auto status = memory_pool_->allocate(size, reinterpret_cast<void **>(&ptr));
  if (!status.ok()) {
    throw std::runtime_error("could not allocate memory: " + status.message());
  }

  auto buffer(libstf::make_buffer(memory_pool_, ptr, size, size));
  tlb_manager_->ensure_tlb_mapping(buffer->ptr, buffer->size);

  return std::move(buffer);
}

libstf::stream_mask_t Reader::decoder_mask() const {
  libstf::stream_mask_t mask;
  mask.set(decoder_);
  return mask;
}

const metadata::Metadata &Reader::metadata() const { return meta_; }

void Reader::enqueue_column_chunk(size_t chunk, size_t column) {
  Profiler::open_regions({reader_prefix + "enqueue_column_chunk"});

  if (chunk >= meta_.groups.size()) {
    throw std::runtime_error("attempted to parse chunk which is out of bounds");
  }
  auto group = meta_.groups[chunk];

  if (column >= group.chunks.size()) {
    throw std::runtime_error(
        "attempted to parse column chunk which is out of bounds");
  }
  auto column_chunk = group.chunks[column];

  // std::cout << "configuring column chunk compression = " <<
  // column_chunk.compression << ", num_values = " << column_chunk.num_values <<
  // ", hybrid_num_values = " << column_chunk.hybrid_num_values << std::endl;
  column_chunk_config_.process_column_chunk(
      decoder_, column_chunk.compression, column_chunk.num_values,
      column_chunk.hybrid_num_values, column_chunk.type);

  // Storing the result handle in the queue
  auto output_handle =
      output_buffer_manager_->acquire_output_handle(decoder_mask());
  auto expected_bytes =
      libstf::size_of(column_chunk.type) * column_chunk.num_values;
  std::cout << "expecting bytes " << expected_bytes << std::endl;

  if (column_chunk.dictionary != std::nullopt) {
    page_config_.process_page(decoder_, PageType::DICT,
                              column_chunk.dictionary->encoding, 0, false);
    send_page(*column_chunk.dictionary, PageType::DICT);
  }

  size_t i = 0;
  for (auto page : column_chunk.data) {
    bool last = i == column_chunk.data.size() - 1;
    page_config_.process_page(decoder_, PageType::DATA, page.encoding,
                              page.num_values, last);
    send_page(page, PageType::DATA);
    ++i;
  }

  queue_.push(output_handle);

  // std::cout << "enqueue_column_chunk over" << std::endl;
  Profiler::close_regions({reader_prefix + "enqueue_column_chunk"});
}

bool Reader::has_next_column_chunk() { return !queue_.empty(); }

std::vector<std::shared_ptr<libstf::Buffer>> Reader::next_column_chunk() {
  Profiler::open_regions({reader_prefix + "next_column_chunk"});
  // std::cout << "next_column_chunk start" << std::endl;

  auto output_handle = queue_.front();
  queue_.pop();

  std::vector<std::shared_ptr<libstf::Buffer>> bufs;

  while (output_handle->stream_has_more_output(decoder_)) {
    // std::cout << "fpga has more output, getting it" << std::endl;
    auto buf = output_handle->get_next_stream_output(decoder_);
    bufs.push_back(std::move(buf));
  }

  if (bufs.size() > 1) {
    std::cout << "done receiving output, got " << bufs.size() << " buffers"
              << std::endl;
  }

  Profiler::close_regions({reader_prefix + "next_column_chunk"});

  // std::cout << "next_column_chunk over" << std::endl;
  return bufs;
}

} // namespace parcore
