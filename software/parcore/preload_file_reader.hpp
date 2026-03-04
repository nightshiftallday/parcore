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
  std::unordered_map<metadata::Page, std::shared_ptr<libstf::Buffer>> pages_;

public:
  PreloadFileReader(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
                    std::shared_ptr<libstf::MemoryPool> memory_pool,
                    const metadata::Metadata &meta,
                    std::shared_ptr<arrow::io::RandomAccessFile> file);

protected:
  std::shared_ptr<libstf::Buffer>
  load_page(std::shared_ptr<arrow::io::RandomAccessFile> file,
            const metadata::Page &page);

  std::shared_ptr<libstf::Buffer> get_page_data(const metadata::Page &page,
                                                PageType page_type) override;
};

} // namespace parcore
