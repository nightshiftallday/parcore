#pragma once

#include <parcore/hardware_reader.hpp>

namespace parcore {

class MemoryReader : public HardwareReader {

public:
  MemoryReader(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
               std::shared_ptr<libstf::MemoryPool> memory_pool,
               const metadata::Metadata &meta,
               std::shared_ptr<libstf::Buffer> data);

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk() override;

protected:
  std::shared_ptr<libstf::Buffer> get_page_data(const metadata::Page &page,
                                                PageType page_type) override;

private:
  std::shared_ptr<libstf::Buffer> data_;
  std::deque<std::vector<std::shared_ptr<libstf::Buffer>>> buffers_;
};

} // namespace parcore
