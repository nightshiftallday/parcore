#include <arrow/array.h>
#include <arrow/array/data.h>
#include <arrow/chunked_array.h>
#include <parquet/file_reader.h>

#include <libstf/profiling.hpp>
#include <parcore/cpu/cpu_reader.hpp>
#include <stdexcept>

using libstf::Profiler;

namespace parcore {

namespace cpu {

const std::string prefix = "parcore::HybridReader::";

std::unique_ptr<parquet::arrow::FileReader>
open_reader(std::shared_ptr<arrow::io::RandomAccessFile> file,
            arrow::MemoryPool *memory_pool, bool use_threads) {
  Profiler::open_regions({prefix + "open_reader"});
  parquet::arrow::FileReaderBuilder builder;
  auto status = builder.Open(file);
  if (!status.ok()) {
    throw std::runtime_error("could not open file with reader builder: " +
                             status.message());
  }
  parquet::ArrowReaderProperties props;
  props.set_use_threads(use_threads);
  if (memory_pool != nullptr)
    builder.memory_pool(memory_pool);
  builder.properties(props);

  std::unique_ptr<parquet::arrow::FileReader> reader;
  status = builder.Build(&reader);
  if (!status.ok()) {
    throw std::runtime_error("could not build reader: " + status.message());
  }
  Profiler::close_regions({prefix + "open_reader"});
  return std::move(reader);
}

CPUReader::CPUReader(std::shared_ptr<arrow::io::RandomAccessFile> file,
                     arrow::MemoryPool *memory_pool, bool use_threads)
    : file_reader_(std::move(open_reader(file, memory_pool, use_threads))) {}

const metadata::Metadata &CPUReader::metadata() const {
  throw std::logic_error("CPUReader::metadata() is not implemented");
}

inline void CPUReader::read_column_chunk(Job *job) {
  auto status = job->reader->Read(&job->out);
  if (!status.ok()) {
    throw std::runtime_error("could not read column chunk: " +
                             status.message());
  }
}

void CPUReader::enqueue_column_chunk(size_t chunk, size_t column) {
  Profiler::open_regions({prefix + "enqueue_column_chunk"});
  auto rg = file_reader_->RowGroup(chunk);
  auto reader = rg->Column(column);

  std::shared_ptr<arrow::ChunkedArray> out;
  auto job = new Job{
      .reader = reader,
      .out = out,
  };
  std::thread thread(read_column_chunk, job);

  queue_.push({std::move(thread), job});
  Profiler::close_regions({prefix + "enqueue_column_chunk"});
}

bool CPUReader::has_next_column_chunk() { return !queue_.empty(); }

std::shared_ptr<arrow::ChunkedArray> CPUReader::next_column_chunk() {
  assert(!queue_.empty());
  Profiler::open_regions({prefix + "next_column_chunk"});

  auto &pair = queue_.front();
  pair.first.join();
  auto out = std::move(pair.second->out);
  delete pair.second;
  queue_.pop();

  Profiler::close_regions({prefix + "next_column_chunk"});
  return std::move(out);
}

} // namespace cpu

} // namespace parcore
