#include <cstring>
#include <optional>
#include <stdexcept>

#include <coyote/cThread.hpp>
#include <libstf/profiling.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>
#include <parcore/reader.hpp>

using libstf::profiler;

namespace parcore {

const std::string reader_prefix = "parcore::Reader::";

void Reader::enqueue_stream_input(const libstf::Buffer &buffer) {
  profiler::open_regions({reader_prefix + "enqueue_stream_input"});
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
    profiler::open_regions({reader_prefix + "local_read"});
    cthread->invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
    profiler::close_regions({reader_prefix + "local_read"});
  }
  profiler::close_regions({reader_prefix + "enqueue_stream_input"});
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
  return std::move(buffer);
}

void Reader::send_page(const metadata::ColumnChunk &chunk,
                       const metadata::Page &page, PageType page_type) {
  profiler::open_regions({reader_prefix + "send_page"});
  auto byte_ptr = static_cast<const std::byte *>(data->ptr);

  auto buffer = libstf::Buffer{
      .ptr = const_cast<void *>(
          reinterpret_cast<const void *>(byte_ptr + page.offset)),
      .size = page.size,
      .capacity = data->capacity - page.offset,
  };

  enqueue_stream_input(buffer);

  profiler::close_regions({reader_prefix + "send_page"});
}

void Reader::enqueue_column_chunk(size_t chunk, size_t column) {
  profiler::open_regions({reader_prefix + "enqueue_column_chunk"});

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
    send_page(column_chunk, *column_chunk.dictionary, PageType::DICT);
  }

  config.process_page(stream, column_chunk.compression, PageType::DATA,
                      column_chunk.data.encoding, column_chunk.num_values,
                      column_chunk.type);
  send_page(column_chunk, column_chunk.data, PageType::DATA);

  queue.push(column_chunk);

  profiler::close_regions({reader_prefix + "enqueue_column_chunk"});
}

std::shared_ptr<libstf::Buffer> Reader::next_column_chunk() {
  profiler::open_regions({reader_prefix + "next_column_chunk"});

  auto column_chunk = queue.front();
  queue.pop();

  auto size = libstf::size_of(column_chunk.type) * column_chunk.num_values;
  auto mem = allocate_buffer(size);
  tlb->ensure_tlb_mapping(mem->ptr, mem->capacity);

  coyote::localSg result_sg = {
      .addr = mem->ptr,
      .len = static_cast<uint32_t>(size),
      .stream = coyote::STRM_HOST,
      .dest = 0,
  };

  profiler::open_regions({reader_prefix + "local_write"});
  cthread->clearCompleted();
  cthread->invoke(coyote::CoyoteOper::LOCAL_WRITE, result_sg);
  while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) < 1)
    ;
  profiler::close_regions({reader_prefix + "local_write"});

  profiler::close_regions({reader_prefix + "next_column_chunk"});

  return std::move(mem);
}

} // namespace parcore
