#include "cpu.hpp"

#include <arrow/buffer.h>
#include <memory>

#include <parquet/arrow/reader.h>
#include <parquet/column_page.h>
#include <parquet/metadata.h>
#include <parquet/platform.h>
#include <parquet/types.h>
#include <stdexcept>

#include <libstf/profiling.hpp>

using libstf::profiler;

namespace parcore {
namespace cpu {

InMemoryRandomAccessFile::InMemoryRandomAccessFile(
    const std::vector<uint8_t> &data)
    : data_(data), position_(0), is_closed(false) {}

arrow::Result<int64_t>
InMemoryRandomAccessFile::ReadAt(int64_t position, int64_t nbytes, void *out) {
  if (nbytes > 0) {
    std::memcpy(out, data_.data() + position, static_cast<size_t>(nbytes));
    position_ += nbytes;
  }
  return nbytes;
}

arrow::Result<std::shared_ptr<arrow::Buffer>>
InMemoryRandomAccessFile::ReadAt(int64_t position, int64_t nbytes) {
  return std::make_shared<arrow::Buffer>(
      (const uint8_t *)data_.data() + position, nbytes);
}

arrow::Result<int64_t> InMemoryRandomAccessFile::Read(int64_t nbytes,
                                                      void *out) {
  return ReadAt(position_, nbytes, out);
}

arrow::Result<std::shared_ptr<arrow::Buffer>>
InMemoryRandomAccessFile::Read(int64_t nbytes) {
  return ReadAt(position_, nbytes);
}

arrow::Result<int64_t> InMemoryRandomAccessFile::GetSize() {
  return data_.size();
}

arrow::Result<int64_t> InMemoryRandomAccessFile::Tell() const {
  return position_;
}

arrow::Status InMemoryRandomAccessFile::Seek(int64_t position) {
  position_ = position;
  return arrow::Status::OK();
}

arrow::Status InMemoryRandomAccessFile::Close() {
  is_closed = true;
  return arrow::Status::OK();
}

bool InMemoryRandomAccessFile::closed() const { return is_closed; }

std::shared_ptr<arrow::ChunkedArray>
read_column_chunk(std::shared_ptr<arrow::io::RandomAccessFile> file,
                  size_t chunk, size_t column) {
  profiler::open_regions({"read_column_chunk", "builder"});
  parquet::arrow::FileReaderBuilder builder;
  auto status = builder.Open(file);
  if (!status.ok()) {
    throw std::runtime_error("could not open file with reader builder: " +
                             status.message());
  }
  parquet::ArrowReaderProperties props;
  props.set_use_threads(false);
  builder.properties(props);

  std::unique_ptr<parquet::arrow::FileReader> reader;
  status = builder.Build(&reader);
  if (!status.ok()) {
    throw std::runtime_error("could not build reader: " + status.message());
  }
  profiler::close_regions({"builder"});

  auto rg = reader->RowGroup(chunk);
  auto col_reader = rg->Column(column);

  std::shared_ptr<arrow::ChunkedArray> out;
  profiler::open_regions({"read"});
  status = col_reader->Read(&out);
  if (!status.ok()) {
    throw std::runtime_error("could not read column chunk: " +
                             status.message());
  }

  profiler::close_regions({"read_column_chunk", "read"});
  return std::move(out);
}

} // namespace cpu
} // namespace parcore
