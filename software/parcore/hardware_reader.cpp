#include <cstring>

#include <coyote/cThread.hpp>
#include <libstf/profiling.hpp>
#include <parcore/configuration.hpp>
#include <parcore/hardware_reader.hpp>
#include <parcore/metadata/metadata.hpp>

using libstf::Profiler;

namespace parcore {

const std::string reader_prefix = "parcore::Reader::";

HardwareReader::HardwareReader(
    std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    const metadata::Metadata &meta)
    : column_chunk_decoder_(std::move(column_chunk_decoder)),
      memory_pool_(std::move(memory_pool)), meta_(meta),
      decoder_(column_chunk_decoder_->decoder()) {
  assert(column_chunk_decoder_ != nullptr);
  assert(memory_pool_ != nullptr);
}

std::shared_ptr<libstf::Buffer> HardwareReader::allocate_buffer(size_t size) {
  void *ptr;
  auto status = memory_pool_->allocate(size, reinterpret_cast<void **>(&ptr));
  if (!status.ok()) {
    throw std::runtime_error("could not allocate memory: " + status.message());
  }

  return std::move(libstf::make_buffer(memory_pool_, ptr, size, size));
}

const metadata::Metadata &HardwareReader::metadata() const { return meta_; }
const libstf::stream_t &HardwareReader::decoder() const { return decoder_; }

void HardwareReader::enqueue_column_chunk(size_t chunk, size_t column) {
  Profiler::open_regions({reader_prefix + "enqueue_column_chunk"});

  auto column_chunk = metadata::get_column_chunk(meta_, chunk, column);

  auto handle = column_chunk_decoder_->decode_column_chunk(column_chunk);
  handle->add_chunk(get_chunk_data(column_chunk));

  auto output_handle = std::move(*handle).done();
  output_queue_.push({column_chunk, output_handle});

  Profiler::close_regions({reader_prefix + "enqueue_column_chunk"});
}

bool HardwareReader::has_next_column_chunk() { return !output_queue_.empty(); }

std::vector<std::shared_ptr<libstf::Buffer>>
HardwareReader::next_column_chunk() {
  Profiler::open_regions({reader_prefix + "next_column_chunk"});
  assert(!output_queue_.empty());

  auto [column_chunk, output_handle] = output_queue_.front();
  output_queue_.pop();

  // Values live on the decoder's values stream, which is no longer the decoder
  // index itself: PairedOutputWriter puts values on 2I and the string heap on
  // 2I + 1. This path only surfaces values, so it cannot serve BYTE_ARRAY
  // columns - see examples/readparquet for the two-stream handling.
  auto values_stream = column_chunk_decoder_->values_stream();
  std::vector<std::shared_ptr<libstf::Buffer>> chunks;
  while (output_handle->stream_has_more_output(values_stream)) {
    auto buf = output_handle->get_next_stream_output(values_stream);
    chunks.push_back(std::move(buf));
  }

  column_chunk_decoder_->finished_decoding_column_chunk(column_chunk);

  Profiler::close_regions({reader_prefix + "next_column_chunk"});
  return chunks;
}

} // namespace parcore
