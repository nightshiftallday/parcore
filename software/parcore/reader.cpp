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
    sg.dest = stream;

    auto last_transfer = off + coyote::MAX_TRANSFER_SIZE >= buffer.size;
    Profiler::open_regions({reader_prefix + "local_read"});
    cthread->invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
    Profiler::close_regions({reader_prefix + "local_read"});
  }
  Profiler::close_regions({reader_prefix + "enqueue_stream_input"});
}

Reader::ColumnChunkData::ColumnChunkData(std::shared_ptr<libstf::Buffer> buffer,
                                         const metadata::ColumnChunk &cc)
    : buffer(std::move(buffer)), next_allocation(0) {
  allocations.reserve(cc.data.size());

  auto cell_size = libstf::size_of(cc.type);
  size_t offset = 0;
  for (auto page : cc.data) {
    auto size = cell_size * page.num_values;
    allocations.push_back({offset, size});
    offset += size;
  }
}

bool Reader::ColumnChunkData::is_full() {
  return next_allocation >= allocations.size();
}

Reader::Reader(std::shared_ptr<coyote::cThread> cthread,
               std::shared_ptr<libstf::MemoryPool> pool,
               std::shared_ptr<libstf::TLBManager> tlb,
               PageDecoderConfig config, const metadata::Metadata &meta,
               std::shared_ptr<libstf::Buffer> data, libstf::stream_t stream)
    : cthread(cthread), pool(pool), tlb(tlb), config(config), meta(meta),
      data(data), stream(stream) {}

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

void Reader::ensure_last_column_chunk_was_collected() {
  if (queue.size() <= 0)
    return;

  auto &ccd = queue.front();
  if (!ccd.is_full())
    collect_output(ccd);
}

void Reader::collect_output(ColumnChunkData &ccd) {
  Profiler::open_regions({reader_prefix + "collect_output"});

  auto alloc = ccd.allocations[ccd.next_allocation];
  std::cout << "collecting output at " << std::get<0>(alloc) << " "
            << std::get<1>(alloc) << std::endl;
  coyote::localSg result_sg = {
      .addr = static_cast<uint8_t *>(ccd.buffer->ptr) + std::get<0>(alloc),
      .len = static_cast<uint32_t>(std::get<1>(alloc)),
      .stream = coyote::STRM_HOST,
      .dest = stream,
  };

  Profiler::open_regions({reader_prefix + "local_write"});
  cthread->clearCompleted();
  cthread->invoke(coyote::CoyoteOper::LOCAL_WRITE, result_sg);
  while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) < 1)
    ;
  Profiler::close_regions({reader_prefix + "local_write"});

  ++ccd.next_allocation;
  Profiler::close_regions({reader_prefix + "collect_output"});
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

  if (column_chunk.dictionary != std::nullopt) {
    config.process_page(stream, column_chunk.compression, PageType::DICT,
                        column_chunk.dictionary->encoding, 0,
                        column_chunk.type);
    send_page(*column_chunk.dictionary, PageType::DICT);
  }

  ensure_last_column_chunk_was_collected();

  auto cell_size = libstf::size_of(column_chunk.type);
  auto size = cell_size * column_chunk.num_values;
  ColumnChunkData ccd(allocate_buffer(size), column_chunk);

  size_t i = 0;
  for (auto page : column_chunk.data) {
    if (i > 0 && !ccd.is_full()) {
      collect_output(ccd);
    }

    config.process_page(stream, column_chunk.compression, PageType::DATA,
                        page.encoding, page.num_values, column_chunk.type);
    send_page(page, PageType::DATA);

    ++i;
  }

  queue.push(ccd);

  Profiler::close_regions({reader_prefix + "enqueue_column_chunk"});
}

bool Reader::has_next_column_chunk() { return !queue.empty(); }

std::shared_ptr<libstf::Buffer> Reader::next_column_chunk() {
  Profiler::open_regions({reader_prefix + "next_column_chunk"});

  auto ccd = queue.front();
  queue.pop();

  if (!ccd.is_full())
    collect_output(ccd);

  Profiler::close_regions({reader_prefix + "next_column_chunk"});

  return std::move(ccd.buffer);
}

} // namespace parcore
