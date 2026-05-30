#include <stdexcept>

#include <libstf/profiling.hpp>
#include <parcore/file_reader.hpp>
#include <parcore/metadata/metadata.hpp>

using libstf::Profiler;

namespace parcore {

FileReader::FileReader(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
                       std::shared_ptr<libstf::MemoryPool> memory_pool,
                       const metadata::Metadata &meta,
                       std::shared_ptr<arrow::io::RandomAccessFile> file)
    : HardwareReader(std::move(column_chunk_decoder), std::move(memory_pool),
                     meta),
      file_(std::move(file)) {}

const std::string prefix = "parcore::FileReader::";

// The column chunk buffer is kept alive in buffers_ until next_column_chunk()
// returns, at which point the FPGA has consumed it.
std::shared_ptr<libstf::Buffer>
FileReader::get_chunk_data(const metadata::ColumnChunk &column_chunk) {
  Profiler::open_regions({prefix + "get_chunk_data"});

  auto buffer = allocate_buffer(column_chunk.total_compressed_size);

  Profiler::open_regions({prefix + "read_file"});
  auto seek_status = file_->Seek(column_chunk.offset);
  if (!seek_status.ok())
    throw std::runtime_error("error while seeking to column chunk: " +
                             seek_status.message());
  auto read_status =
      file_->Read(column_chunk.total_compressed_size, buffer->ptr);
  if (!read_status.ok())
    throw std::runtime_error("error while reading column chunk: " +
                             read_status.status().message());
  assert(read_status.ValueOrDie() == column_chunk.total_compressed_size);

  Profiler::close_regions({prefix + "read_file"});

  buffers_.push_back(buffer);

  Profiler::close_regions({prefix + "get_chunk_data"});
  return buffer;
}

std::vector<std::shared_ptr<libstf::Buffer>> FileReader::next_column_chunk() {
  auto result = HardwareReader::next_column_chunk();
  assert(!buffers_.empty());
  buffers_.pop_front();
  return result;
}

} // namespace parcore
