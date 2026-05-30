#include <libstf/profiling.hpp>
#include <parcore/preload_file_reader.hpp>

using libstf::Profiler;

namespace parcore {

PreloadFileReader::PreloadFileReader(
    std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
    std::shared_ptr<libstf::MemoryPool> memory_pool,
    const metadata::Metadata &meta,
    std::shared_ptr<arrow::io::RandomAccessFile> file)
    : HardwareReader(std::move(column_chunk_decoder), std::move(memory_pool),
                     meta) {
  for (auto &row_group : meta_.groups) {
    for (auto &column_chunk : row_group.chunks) {
      chunks_.insert({column_chunk, load_chunk(file, column_chunk)});
    }
  }
}

const std::string prefix = "parcore::PreloadFileReader::";

std::shared_ptr<libstf::Buffer>
PreloadFileReader::load_chunk(std::shared_ptr<arrow::io::RandomAccessFile> file,
                              const metadata::ColumnChunk &column_chunk) {
  Profiler::open_regions({prefix + "load_chunk"});

  auto buffer = allocate_buffer(column_chunk.total_compressed_size);

  auto seek_status = file->Seek(column_chunk.offset);
  if (!seek_status.ok())
    throw std::runtime_error("error while seeking to column chunk: " +
                             seek_status.message());
  auto read_status =
      file->Read(column_chunk.total_compressed_size, buffer->ptr);
  if (!read_status.ok())
    throw std::runtime_error("error while reading column chunk: " +
                             read_status.status().message());
  assert(read_status.ValueOrDie() == column_chunk.total_compressed_size);

  Profiler::close_regions({prefix + "load_chunk"});
  return std::move(buffer);
}

std::shared_ptr<libstf::Buffer>
PreloadFileReader::get_chunk_data(const metadata::ColumnChunk &column_chunk) {
  assert(chunks_.find(column_chunk) != chunks_.end());
  return chunks_[column_chunk];
}

} // namespace parcore
