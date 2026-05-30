#pragma once

#include <arrow/io/file.h>

#include <parcore/hardware_reader.hpp>

namespace parcore {

/*
 * This reader preloads all pages in memory to avoid any overhead when measuring
 * performance of the decoder.
 */
class PreloadFileReader : public HardwareReader {
private:
  std::unordered_map<metadata::ColumnChunk, std::shared_ptr<libstf::Buffer>> chunks_;

public:
  PreloadFileReader(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
                    std::shared_ptr<libstf::MemoryPool> memory_pool,
                    const metadata::Metadata &meta,
                    std::shared_ptr<arrow::io::RandomAccessFile> file);

protected:
  std::shared_ptr<libstf::Buffer>
  load_chunk(std::shared_ptr<arrow::io::RandomAccessFile> file,
             const metadata::ColumnChunk &column_chunk);

  std::shared_ptr<libstf::Buffer>
  get_chunk_data(const metadata::ColumnChunk &column_chunk) override;
};

} // namespace parcore
