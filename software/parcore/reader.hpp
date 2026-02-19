#pragma once

#include <memory>
#include <queue>

#include <coyote/cThread.hpp>
#include <libstf/buffer.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/tlb_manager.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>

namespace parcore {

class Reader {
private:
  std::shared_ptr<coyote::cThread> cthread;
  std::shared_ptr<libstf::MemoryPool> pool;
  std::shared_ptr<libstf::TLBManager> tlb;
  ColumnChunkDecoderConfig column_chunk_config;
  PageDecoderConfig page_config;
  metadata::Metadata meta;
  std::shared_ptr<libstf::Buffer> data;
  libstf::stream_t decoder;

  class ColumnChunkData {
  public:
    std::shared_ptr<libstf::Buffer> buffer;
    bool full;

    ColumnChunkData(std::shared_ptr<coyote::cThread> cthread,
                    std::shared_ptr<libstf::Buffer> buffer,
                    const metadata::ColumnChunk &cc, libstf::stream_t decoder);

    bool is_full();

    void collect(std::shared_ptr<coyote::cThread> cthread,
                 libstf::stream_t decoder);
  };

  std::queue<ColumnChunkData> queue;
  std::shared_ptr<ColumnChunkData> in_flight_page;

public:
  Reader(std::shared_ptr<coyote::cThread> cthread,
         std::shared_ptr<libstf::MemoryPool> pool,
         std::shared_ptr<libstf::TLBManager> tlb,
         ColumnChunkDecoderConfig column_chunk_config,
         PageDecoderConfig page_config, const metadata::Metadata &meta,
         std::shared_ptr<libstf::Buffer> data, libstf::stream_t decoder = 0);

  const metadata::Metadata &metadata() const;

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   */
  void enqueue_column_chunk(size_t chunk, size_t column);

  /**
   * Returns whether there is a column chunk enqueued for processing. If this
   * function returns true, then the consumer can call `next_column_chunk` to
   * retrieve the output data, potentially blocking on until the acceleartor
   * is done processing.
   */
  bool has_next_column_chunk();

  /**
   * Retrieves the next column chunk that has been enqueued for processing.
   */
  std::shared_ptr<libstf::Buffer> next_column_chunk();

protected:
  std::shared_ptr<libstf::Buffer> allocate_buffer(size_t size);

  void enqueue_stream_input(const libstf::Buffer &buffer);

  // Sends a dictionary or data pge to be processed by the accelerator
  virtual void send_page(const metadata::Page &page, PageType page_type);
};

} // namespace parcore
