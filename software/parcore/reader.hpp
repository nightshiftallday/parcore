#pragma once

#include <coyote/cThread.hpp>
#include <cstdint>
#include <libstf/buffer.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/tlb_manager.hpp>
#include <memory>
#include <parcore/fpga.hpp>
#include <parcore/metadata/metadata.hpp>
#include <queue>

namespace parcore {

class Reader {
private:
  std::shared_ptr<coyote::cThread> cthread;
  std::shared_ptr<libstf::MemoryPool> pool;
  std::shared_ptr<libstf::TLBManager> tlb;
  metadata::Metadata meta;
  std::shared_ptr<libstf::Buffer> data;

  std::queue<metadata::ColumnChunk> queue;

public:
  Reader(std::shared_ptr<coyote::cThread> cthread,
         std::shared_ptr<libstf::MemoryPool> pool,
         std::shared_ptr<libstf::TLBManager> tlb,
         const metadata::Metadata &meta, std::shared_ptr<libstf::Buffer> data);

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   */
  void enqueue_column_chunk(size_t chunk, size_t column);

  /**
   * Retrieves the next column chunk that has been enqueued for processing.
   */
  std::shared_ptr<libstf::Buffer> next_column_chunk();

private:
  std::shared_ptr<libstf::Buffer> allocate_buffer(size_t size);

  void send_command(const metadata::ColumnChunk &column_chunk,
                    const metadata::Page &page, PageType page_type);

  void send_page(const metadata::ColumnChunk &column_chunk,
                 const metadata::Page &page, PageType page_type);
};

/*
 * Sends the necessary commands and data to the parcore hardware decoder to
 * parse the provided column chunk.
 *
 * NOTE: This assumes that the data in `data` has already been mapped with
 * `userMap` in the provided cThread.
 */
std::shared_ptr<libstf::Buffer>
read_column_chunk(std::shared_ptr<coyote::cThread> cthread,
                  libstf::MemoryPool &pool, const metadata::Metadata &meta,
                  const std::vector<uint8_t> data, size_t chunk, size_t column);

} // namespace parcore
