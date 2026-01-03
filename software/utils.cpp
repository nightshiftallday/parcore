#include "utils.hpp"
#include "fpga.hpp"
#include "metadata.hpp"

#include <arrow/buffer.h>
#include <arrow/result.h>
#include <arrow/type_fwd.h>
#include <memory>
#include <optional>
#include <parquet/types.h>
#include <stdexcept>

namespace parcore {
namespace utils {

void send_cmd(std::shared_ptr<coyote::cThread> cthread, ParcoreCommand cmd) {
  auto cmd_len = static_cast<uint32_t>(cmd.size());
  auto cmd_mem =
      (uint8_t *)cthread->getMem({coyote::CoyoteAllocType::REG, cmd_len});
  if (!cmd_mem) {
    throw std::runtime_error("Could not allocate cmd memory");
  }
  memcpy(cmd_mem, cmd.data(), cmd_len);
  coyote::localSg cmd_sg = {
      .addr = cmd_mem,
      .len = cmd_len,
      .stream = coyote::STRM_HOST,
      .dest = 0,
  };

  cthread->clearCompleted();
  cthread->invoke(coyote::CoyoteOper::LOCAL_READ, cmd_sg);
  while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1)
    ;
}

void send_page(std::shared_ptr<coyote::cThread> cthread,
               const metadata::ColumnChunk &chunk, const metadata::Page &page,
               PageType page_type, const std::vector<uint8_t> data) {
  auto cmd = command_for_column_chunk_page(chunk, page, page_type);
  send_cmd(cthread, cmd);

  auto addr = data.data() + page.offset;
  coyote::localSg data_sg = {
      .addr = const_cast<void *>(reinterpret_cast<const void *>(addr)),
      .len = static_cast<uint32_t>(page.size),
      .stream = coyote::STRM_HOST,
      .dest = 0,
  };

  cthread->clearCompleted();
  cthread->invoke(coyote::CoyoteOper::LOCAL_READ, data_sg);
  while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1)
    ;
}

std::shared_ptr<arrow::ChunkedArray>
get_result(std::shared_ptr<coyote::cThread> cthread, arrow::MemoryPool *pool,
           const metadata::ColumnChunk &chunk) {
  auto bytes = type_data_size(chunk.type) * chunk.num_values;
  auto buffer_result = arrow::AllocateBuffer(bytes, pool);
  if (!buffer_result.ok()) {
    throw std::runtime_error("could not allocate result Arrow buffer: " +
                             buffer_result.status().message());
  }
  auto _buffer = std::move(buffer_result).ValueOrDie();
  std::shared_ptr<arrow::Buffer> buffer = std::move(_buffer);

  coyote::localSg result_sg = {
      .addr = const_cast<void *>(
          reinterpret_cast<const void *>(buffer->mutable_data())),
      .len = static_cast<uint32_t>(bytes),
      .stream = coyote::STRM_HOST,
      .dest = 0,
  };

  cthread->invoke(coyote::CoyoteOper::LOCAL_WRITE, result_sg);
  while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1)
    ;

  auto array_data = arrow::ArrayData::Make(type_to_arrow(chunk.type), bytes,
                                           {nullptr, buffer});
  auto array = arrow::MakeArray(array_data);
  return std::make_shared<arrow::ChunkedArray>(array);
}

std::shared_ptr<arrow::ChunkedArray>
read_column_chunk(std::shared_ptr<coyote::cThread> cthread,
                  arrow::MemoryPool *pool, const metadata::Metadata &meta,
                  const std::vector<uint8_t> data, size_t chunk,
                  size_t column) {
  if (chunk >= meta.groups.size()) {
    throw std::runtime_error("attempted to get chunk which is out of bounds");
  }
  auto group = meta.groups[chunk];

  if (chunk >= group.chunks.size()) {
    throw std::runtime_error(
        "attempted to get column chunk which is out of bounds");
  }
  auto column_chunk = group.chunks[column];

  if (column_chunk.dictionary != std::nullopt) {
    send_page(cthread, column_chunk, *column_chunk.dictionary, PageType::DICT,
              data);
  }
  send_page(cthread, column_chunk, column_chunk.data, PageType::DATA, data);

  return get_result(cthread, pool, column_chunk);
}

} // namespace utils
} // namespace parcore
