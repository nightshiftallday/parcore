#pragma once

#include <memory>

#include <coyote/cThread.hpp>
#include <libstf/buffer.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/output_buffer_manager.hpp>
#include <libstf/tlb_manager.hpp>
#include <parcore/column_chunk_decoder.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>
#include <queue>

namespace parcore {

class HardwareReader {

public:
  HardwareReader(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
                 std::shared_ptr<libstf::MemoryPool> memory_pool,
                 const metadata::Metadata &meta);

  [[nodiscard]] const metadata::Metadata &metadata() const;
  [[nodiscard]] const libstf::stream_t &decoder() const;

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   *
   * @param chunk      The index of the chunk to decode
   * @param column     The index of the column to decode
   */
  virtual void enqueue_column_chunk(size_t chunk, size_t column);

  /**
   * Returns whether there is a column chunk enqueued for processing. If this
   * function returns true, then the consumer can call `next_column_chunk` to
   * retrieve the output data, potentially blocking on until the acceleartor
   * is done processing.
   */
  [[nodiscard]] virtual bool has_next_column_chunk();

  /**
   * Retrieves the next column chunk that has been enqueued for processing.
   */
  [[nodiscard]] virtual std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk();

protected:
  std::shared_ptr<libstf::MemoryPool> memory_pool_;
  std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder_;
  metadata::Metadata meta_;
  libstf::stream_t decoder_;
  std::queue<std::shared_ptr<libstf::OutputHandle>> output_queue_;

  std::shared_ptr<libstf::Buffer> allocate_buffer(size_t size);

  // Retrieves the data to be sent for the given page
  virtual std::shared_ptr<libstf::Buffer>
  get_page_data(const metadata::Page &page, PageType page_type) = 0;
};

} // namespace parcore
