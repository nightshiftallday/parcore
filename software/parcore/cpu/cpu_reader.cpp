#include <arrow/array.h>
#include <arrow/array/data.h>
#include <arrow/chunked_array.h>
#include <parquet/file_reader.h>

#include <libstf/profiling.hpp>
#include <parcore/cpu/cpu_reader.hpp>

using libstf::Profiler;

namespace parcore {
namespace cpu {

const std::string prefix = "parcore::HybridReader::";

std::unique_ptr<parquet::arrow::FileReader>
open_reader(std::shared_ptr<arrow::io::RandomAccessFile> file) {
  Profiler::open_regions({prefix + "open_reader"});
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
  Profiler::close_regions({prefix + "open_reader"});
  return std::move(reader);
}

CPUReader::CPUReader(std::shared_ptr<arrow::io::RandomAccessFile> file)
    : file_reader_(std::move(open_reader(file))) {}

void CPUReader::enqueue_column_chunk(size_t chunk, size_t column) {
  Profiler::open_regions({prefix + "enqueue_column_chunk"});
  auto rg = file_reader_->RowGroup(chunk);
  auto col_reader = rg->Column(column);

  queue_.push(col_reader);
  Profiler::close_regions({prefix + "enqueue_column_chunk"});
}

bool CPUReader::has_next_column_chunk() { return !queue_.empty(); }

struct ArrayDeleter {
  ArrayDeleter(std::shared_ptr<arrow::Array> array) : array_(array) {}

  void operator()(libstf::Buffer const *buffer) const { /* TODO */ }

private:
  std::shared_ptr<arrow::Array> array_;
};

std::shared_ptr<libstf::Buffer>
arrow_to_libstf_buffer(std::shared_ptr<arrow::Array> array) {
  auto &buf = array->data()->buffers[1];
  void *ptr = const_cast<uint8_t *>(buf->data());
  size_t bytes = buf->size();
  auto buffer =
      new libstf::Buffer{.ptr = ptr, .size = bytes, .capacity = bytes};
  return std::shared_ptr<libstf::Buffer>(buffer, ArrayDeleter(array));
}

std::vector<std::shared_ptr<libstf::Buffer>> CPUReader::next_column_chunk() {
  assert(!queue_.empty());
  Profiler::open_regions({prefix + "next_column_chunk"});

  auto col_reader = queue_.front();
  assert(col_reader != nullptr);
  queue_.pop();

  std::shared_ptr<arrow::ChunkedArray> out;
  auto status = col_reader->Read(&out);
  if (!status.ok()) {
    throw std::runtime_error("could not read column chunk: " +
                             status.message());
  }

  std::vector<std::shared_ptr<libstf::Buffer>> buffers;
  buffers.reserve(out->num_chunks());
  for (auto array : out->chunks()) {
    auto buf = arrow_to_libstf_buffer(array);
    buffers.push_back(buf);
  }

  Profiler::close_regions({prefix + "next_column_chunk"});
  return buffers;
}

} // namespace cpu
} // namespace parcore
