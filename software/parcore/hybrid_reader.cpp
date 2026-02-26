#include <parquet/arrow/reader.h>

#include <libstf/profiling.hpp>
#include <parcore/base_reader.hpp>
#include <parcore/hybrid_reader.hpp>
#include <parcore/metadata/metadata.hpp>

using libstf::Profiler;

namespace parcore {

const std::string prefix = "parcore::HybridReader::";

HybridReader::HybridReader(std::shared_ptr<Reader> reader,
                           std::shared_ptr<arrow::io::RandomAccessFile> file)
    : reader_(std::move(reader)), file_(std::move(file)) {
  Profiler::open_regions({prefix + "builder"});
  parquet::arrow::FileReaderBuilder builder;
  auto status = builder.Open(file_);
  if (!status.ok()) {
    throw std::runtime_error("could not open file with reader builder: " +
                             status.message());
  }
  parquet::ArrowReaderProperties props;
  props.set_use_threads(false);
  builder.properties(props);

  status = builder.Build(&file_reader_);
  if (!status.ok()) {
    throw std::runtime_error("could not build reader: " + status.message());
  }
  Profiler::close_regions({prefix + "builder"});
}

inline bool can_be_harware_decoded(const metadata::Type &typ) {}

void HybridReader::enqueue_column_chunk(size_t chunk, size_t column) {
  auto column_chunk = get_column_chunk(metadata(), chunk, column);

  // TODO: change type to non-libstf, so we also support BYTE_ARRAY and such.
  if (column_chunk.type) {
  }
}

} // namespace parcore
