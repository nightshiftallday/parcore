#include <libstf/profiling.hpp>
#include <parcore/column_chunk_decoder.hpp>
#include <parcore/reader.hpp>

using libstf::Profiler;

namespace parcore {

ColumnChunkDecoder::ColumnChunkDecoder(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::TLBManager> tlb_manager,
    std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
    std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
    std::shared_ptr<PageDecoderConfig> page_config, libstf::stream_t decoder)
    : cthread_(std::move(cthread)), tlb_manager_(std::move(tlb_manager)),
      output_buffer_manager_(std::move(output_buffer_manager)),
      column_chunk_config_(std::move(column_chunk_config)),
      page_config_(std::move(page_config)), decoder_(decoder),
      column_chunk_enqueued_configs_(0), page_enqueued_configs_(0) {}

const libstf::stream_t &ColumnChunkDecoder::decoder() const { return decoder_; }

ColumnChunkDecoder::Handle::Handle(
    std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
    std::unique_lock<std::mutex> lock,
    std::shared_ptr<libstf::OutputHandle> output_handle, size_t expected_pages)
    : column_chunk_decoder_(std::move(column_chunk_decoder)),
      lock_(std::move(lock)), output_handle_(output_handle), written_pages_(0),
      expected_pages_(expected_pages) {}

void ColumnChunkDecoder::Handle::add_page(
    const std::shared_ptr<libstf::Buffer> &buffer) {
  assert(written_pages_ < expected_pages_);

  // Buffer here could be null to signal that we have providede the data to the
  // hardware trough a side-channel. For example, the RDMA reader would be
  // directly wired into the ColumnChunkDecoder, and thus just configuring the
  // reader is enough to feed data to the decoder, so we don't need to perform
  // any host transfer.
  if (buffer != nullptr)
    column_chunk_decoder_->enqueue_stream_input(buffer);

  ++written_pages_;
}

std::shared_ptr<libstf::OutputHandle> ColumnChunkDecoder::Handle::done() && {
  if (written_pages_ < expected_pages_)
    throw std::runtime_error(
        "Not enough pages have been written when calling done(): " +
        std::to_string(written_pages_) + " so far, expected " +
        std::to_string(expected_pages_));

  // We return the data. The 'this' object (Handle) is destroyed
  // immediately after this call, which triggers the lock's destructor.
  return std::move(output_handle_);
}

const std::string prefix = "parcore::ColumnChunkDecoder";

std::unique_ptr<ColumnChunkDecoder::Handle>
ColumnChunkDecoder::decode_column_chunk(
    const metadata::ColumnChunk &column_chunk) {
  std::unique_lock lock(mtx);
  Profiler::open_regions({prefix + "decode_column_chunk"});
  auto n_pages = num_pages(column_chunk);
  assert(column_chunk_enqueued_configs_ + 1 <
         column_chunk_config_->maximum_num_enqueued_configs());
  assert(page_enqueued_configs_ + n_pages <
         page_config_->maximum_num_enqueued_configs());

  // Storing the result handle in the queue
  auto output_handle =
      output_buffer_manager_->acquire_output_handle(decoder_mask());

  auto type = metadata::to_libstf_type(column_chunk.type);
  column_chunk_config_->process_column_chunk(
      decoder_, column_chunk.compression, column_chunk.num_values,
      column_chunk.hybrid_num_values, type);

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

  column_chunk_enqueued_configs_ += 1;
  page_enqueued_configs_ += n_pages;

  Profiler::close_regions({prefix + "decode_column_chunk"});
  return std::make_unique<Handle>(shared_from_this(), std::move(lock),
                                  output_handle, n_pages);
}

void ColumnChunkDecoder::finished_decoding_column_chunk(
    const metadata::ColumnChunk &column_chunk) {
  std::unique_lock lock(mtx);
  auto n_pages = num_pages(column_chunk);

  column_chunk_enqueued_configs_ -= 1;
  page_enqueued_configs_ -= n_pages;
}

libstf::stream_mask_t ColumnChunkDecoder::decoder_mask() const {
  libstf::stream_mask_t mask;
  mask.set(decoder_);
  return mask;
}

void ColumnChunkDecoder::enqueue_stream_input(
    const std::shared_ptr<libstf::Buffer> &buffer) {
  Profiler::open_regions({prefix + "enqueue_stream_input"});
  auto byte_ptr = static_cast<const std::byte *>(buffer->ptr);
  tlb_manager_->ensure_tlb_mapping(buffer->ptr, buffer->capacity);

  for (size_t off = 0; off < buffer->size; off += coyote::MAX_TRANSFER_SIZE) {
    // Get the address and output_size of this chunk
    auto curr_ptr = (void *)(byte_ptr + off);
    auto input_size = std::min(buffer->size - off, coyote::MAX_TRANSFER_SIZE);

    // Configure the data transfer
    coyote::localSg sg;
    // NOTE: This is a current limitation of coyote, even if the TLB entry is
    // aligned, writing from an address that's not aligned will result in
    // databeats with broken keep.
    assert((reinterpret_cast<uintptr_t>(curr_ptr) % 64) == 0);
    sg.addr = curr_ptr;
    sg.len = input_size;
    sg.stream = coyote::STRM_HOST;
    sg.dest = decoder_;

    auto last_transfer = off + coyote::MAX_TRANSFER_SIZE >= buffer->size;
    cthread_->invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
  }
  Profiler::close_regions({prefix + "enqueue_stream_input"});
}

} // namespace parcore
