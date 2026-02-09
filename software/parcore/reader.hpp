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
  PageDecoderConfig config;
  metadata::Metadata meta;
  std::shared_ptr<libstf::Buffer> data;
  libstf::stream_t stream;

  std::queue<metadata::ColumnChunk> queue;

public:
  Reader(std::shared_ptr<coyote::cThread> cthread,
         std::shared_ptr<libstf::MemoryPool> pool,
         std::shared_ptr<libstf::TLBManager> tlb, PageDecoderConfig config,
         const metadata::Metadata &meta, std::shared_ptr<libstf::Buffer> data,
         libstf::stream_t stream = 0);

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   */
  void enqueue_column_chunk(size_t chunk, size_t column);

  /**
   * Retrieves the next column chunk that has been enqueued for processing.
   */
  std::shared_ptr<libstf::Buffer> next_column_chunk();

protected:
  std::shared_ptr<libstf::Buffer> allocate_buffer(size_t size);

  void enqueue_stream_input(const libstf::Buffer &buffer);

private:
  void send_page(const metadata::ColumnChunk &column_chunk,
                 const metadata::Page &page, PageType page_type);
};

} // namespace parcore
