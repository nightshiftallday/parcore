#include <algorithm>
#include <cstdint>
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

const std::string reader_prefix = "parcore::Reader::";

void Reader::enqueue_stream_input(const libstf::Buffer &buffer) {
  Profiler::open_regions({reader_prefix + "enqueue_stream_input"});
  auto byte_ptr = static_cast<const std::byte *>(buffer.ptr);
  tlb->ensure_tlb_mapping(buffer.ptr, buffer.capacity);

  for (size_t off = 0; off < buffer.size; off += coyote::MAX_TRANSFER_SIZE) {
    // Get the address and output_size of this chunk
    auto curr_ptr = (void *)(byte_ptr + off);
    auto input_size = std::min(buffer.size - off, coyote::MAX_TRANSFER_SIZE);

    // Configure the data transfer
    coyote::localSg sg;
    sg.addr = curr_ptr;
    sg.len = input_size;
    sg.stream = coyote::STRM_HOST;
    sg.dest = decoder;

    std::cout << "sending data at " << std::hex << curr_ptr << " " << std::dec
              << input_size << "..." << std::flush;
    auto last_transfer = off + coyote::MAX_TRANSFER_SIZE >= buffer.size;
    Profiler::open_regions({reader_prefix + "local_read"});
    cthread->clearCompleted();
    cthread->invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
    while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) < 1)
      ;
    std::cout << "done" << std::endl;
    Profiler::close_regions({reader_prefix + "local_read"});
  }
  Profiler::close_regions({reader_prefix + "enqueue_stream_input"});
}

Reader::ColumnChunkData::ColumnChunkData(
    std::shared_ptr<coyote::cThread> cthread,
    std::shared_ptr<libstf::Buffer> buffer, const metadata::ColumnChunk &cc,
    libstf::stream_t decoder)
    : buffer(std::move(buffer)), full(false) {
  // std::cout << "collecting output at " << std::hex << this->buffer->ptr << "
  // " << std::dec << this->buffer->size << std::endl;
  coyote::localSg result_sg = {
      .addr = this->buffer->ptr,
      .len = static_cast<uint32_t>(this->buffer->size),
      .stream = coyote::STRM_HOST,
      .dest = decoder,
  };

  cthread->clearCompleted();
  Profiler::open_regions({reader_prefix + "local_write (invoke)"});
  cthread->invoke(coyote::CoyoteOper::LOCAL_WRITE, result_sg);
  Profiler::close_regions({reader_prefix + "local_write (invoke)"});
}

bool Reader::ColumnChunkData::is_full() { return full; }

void Reader::ColumnChunkData::collect(std::shared_ptr<coyote::cThread> cthread,
                                      libstf::stream_t decoder) {
  Profiler::open_regions({reader_prefix + "collect_output"});

  Profiler::open_regions({reader_prefix + "local_write_complete"});
  std::cout << "waiting on output..." << std::flush;
  while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) < 1)
    ;
  std::cout << "done" << std::endl;
  Profiler::close_regions({reader_prefix + "local_write_complete"});

  full = true;
  Profiler::close_regions({reader_prefix + "collect_output"});
}

Reader::Reader(std::shared_ptr<coyote::cThread> cthread,
               std::shared_ptr<libstf::MemoryPool> pool,
               std::shared_ptr<libstf::TLBManager> tlb,
               ColumnChunkDecoderConfig column_chunk_config,
               PageDecoderConfig page_config, const metadata::Metadata &meta,
               std::shared_ptr<libstf::Buffer> data, libstf::stream_t stream)
    : cthread(cthread), pool(pool), tlb(tlb),
      column_chunk_config(column_chunk_config), page_config(page_config),
      meta(meta), data(data), decoder(stream) {}

std::shared_ptr<libstf::Buffer> Reader::allocate_buffer(size_t size) {
  void *ptr;
  auto status = pool->allocate(size, reinterpret_cast<void **>(&ptr));
  if (!status.ok()) {
    throw std::runtime_error("could not allocate memory: " + status.message());
  }

  auto buffer(libstf::make_buffer(pool, ptr, size, size));
  tlb->ensure_tlb_mapping(buffer->ptr, buffer->size);

  return std::move(buffer);
}

const metadata::Metadata &Reader::metadata() const { return meta; }

void Reader::send_page(const metadata::Page &page, PageType page_type) {
  Profiler::open_regions({reader_prefix + "send_page"});
  auto byte_ptr = static_cast<const std::byte *>(data->ptr);

  auto buffer = libstf::Buffer{
      .ptr = const_cast<void *>(
          reinterpret_cast<const void *>(byte_ptr + page.offset)),
      .size = page.size,
      .capacity = data->capacity - page.offset,
  };

  enqueue_stream_input(buffer);

  Profiler::close_regions({reader_prefix + "send_page"});
}

void Reader::enqueue_column_chunk(size_t chunk, size_t column) {
  Profiler::open_regions({reader_prefix + "enqueue_column_chunk"});

  if (chunk >= meta.groups.size()) {
    throw std::runtime_error("attempted to parse chunk which is out of bounds");
  }
  auto group = meta.groups[chunk];

  if (column >= group.chunks.size()) {
    throw std::runtime_error(
        "attempted to parse column chunk which is out of bounds");
  }
  auto column_chunk = group.chunks[column];

  // std::cout << "configuring column chunk compression = " <<
  // column_chunk.compression << ", num_values = " << column_chunk.num_values <<
  // ", hybrid_num_values = " << column_chunk.hybrid_num_values << std::endl;
  column_chunk_config.process_column_chunk(
      decoder, column_chunk.compression, column_chunk.num_values,
      column_chunk.hybrid_num_values, column_chunk.type);

  // Storing the result handle in the queue
  auto cell_size = libstf::size_of(column_chunk.type);
  auto size = cell_size * column_chunk.num_values;
  ColumnChunkData ccd(cthread, allocate_buffer(size), column_chunk, decoder);

  if (column_chunk.dictionary != std::nullopt) {
    page_config.process_page(decoder, PageType::DICT,
                             column_chunk.dictionary->encoding, 0, false);
    send_page(*column_chunk.dictionary, PageType::DICT);
  }

  size_t i = 0;
  for (auto page : column_chunk.data) {
    bool last = i == column_chunk.data.size() - 1;
    page_config.process_page(decoder, PageType::DATA, page.encoding,
                             page.num_values, last);
    send_page(page, PageType::DATA);
    ++i;
  }

  queue.push(ccd);

  std::cout << "enqueue_column_chunk over" << std::endl;
  Profiler::close_regions({reader_prefix + "enqueue_column_chunk"});
}

bool Reader::has_next_column_chunk() { return !queue.empty(); }

std::shared_ptr<libstf::Buffer> Reader::next_column_chunk() {
  Profiler::open_regions({reader_prefix + "next_column_chunk"});
  std::cout << "next_column_chunk start" << std::endl;

  auto ccd = queue.front();
  queue.pop();

  if (!ccd.is_full())
    ccd.collect(cthread, decoder);

  Profiler::close_regions({reader_prefix + "next_column_chunk"});

  std::cout << "next_column_chunk over" << std::endl;
  return std::move(ccd.buffer);
}

} // namespace parcore
