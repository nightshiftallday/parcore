#include <cstring>
#include <optional>
#include <stdexcept>

#include <coyote/cThread.hpp>
#include <parcore/fpga.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/metadata/utils.hpp>
#include <parcore/profiling.hpp>
#include <parcore/reader.hpp>

namespace parcore {

void enqueue_stream_input(coyote::cThread &cthread, libstf::TLBManager &tlb,
                          const libstf::Buffer &buffer, uint32_t stream) {
  profiler::open_regions({"enqueue_stream_input"});
  auto byte_ptr = static_cast<const std::byte *>(buffer.ptr);
  tlb.ensure_tlb_mapping(buffer.ptr, buffer.capacity);

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
    profiler::open_regions({"local_read"});
    cthread.invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
    profiler::close_regions({"local_read"});
  }
  profiler::close_regions({"enqueue_stream_input"});
}

Reader::Reader(std::shared_ptr<coyote::cThread> cthread,
               std::shared_ptr<libstf::MemoryPool> pool,
               std::shared_ptr<libstf::TLBManager> tlb,
               const metadata::Metadata &meta,
               std::shared_ptr<libstf::Buffer> data)
    : cthread(cthread), pool(pool), tlb(tlb), meta(meta), data(data) {}

std::shared_ptr<libstf::Buffer> Reader::allocate_buffer(size_t size) {
  void *ptr;
  auto status = pool->allocate(size, reinterpret_cast<void **>(&ptr));
  if (!status.ok()) {
    throw std::runtime_error("could not allocate memory: " + status.message());
  }
  auto buffer(libstf::make_buffer(pool, ptr, size, size));
  return std::move(buffer);
}

void Reader::send_command(const metadata::ColumnChunk &column_chunk,
                          const metadata::Page &page, PageType page_type) {
  profiler::open_regions({"send_command"});

  auto mem = allocate_buffer(PARCORE_COMMAND_SIZE);
  auto cmd = command_for_column_chunk_page(column_chunk, page, page_type);
  assert(mem->size == cmd.size());
  std::memcpy(mem->ptr, cmd.data(), cmd.size());

  enqueue_stream_input(*cthread, *tlb, *mem, 0);

  profiler::close_regions({"send_command"});
}

void Reader::send_page(const metadata::ColumnChunk &chunk,
                       const metadata::Page &page, PageType page_type) {
  profiler::open_regions({"send_page"});

  send_command(chunk, page, page_type);
  auto byte_ptr = static_cast<const std::byte *>(data->ptr);
  std::cout << "byte ptr " << std::hex << byte_ptr << " size " << std::dec
            << data->size << std::endl;

  auto buffer = libstf::Buffer{
      .ptr = const_cast<void *>(
          reinterpret_cast<const void *>(byte_ptr + page.offset)),
      .size = page.size,
      .capacity = data->capacity - page.offset,
  };

  enqueue_stream_input(*cthread, *tlb, buffer, 1);

  profiler::close_regions({"send_page"});
}

void Reader::enqueue_column_chunk(size_t chunk, size_t column) {
  profiler::open_regions({"enqueue_column_chunk"});

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
    send_page(column_chunk, *column_chunk.dictionary, PageType::DICT);
  }
  send_page(column_chunk, column_chunk.data, PageType::DATA);

  queue.push(column_chunk);

  profiler::close_regions({"enqueue_column_chunk"});
}

std::shared_ptr<libstf::Buffer> Reader::next_column_chunk() {
  profiler::open_regions({"next_column_chunk"});

  auto column_chunk = queue.front();
  queue.pop();

  auto size = type_data_size(column_chunk.type) * column_chunk.num_values;
  auto mem = allocate_buffer(size);
  tlb->ensure_tlb_mapping(mem->ptr, mem->capacity);

  coyote::localSg result_sg = {
      .addr = mem->ptr,
      .len = static_cast<uint32_t>(size),
      .stream = coyote::STRM_HOST,
      .dest = 0,
  };

  profiler::open_regions({"local_write"});
  cthread->clearCompleted();
  cthread->invoke(coyote::CoyoteOper::LOCAL_WRITE, result_sg);
  while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) < 1)
    ;
  profiler::close_regions({"local_write"});

  profiler::close_regions({"next_column_chunk"});

  return std::move(mem);
}

} // namespace parcore
