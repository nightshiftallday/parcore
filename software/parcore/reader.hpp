#pragma once

#include <memory>
#include <queue>

#include <coyote/cThread.hpp>
#include <libstf/buffer.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/output_buffer_manager.hpp>
#include <libstf/tlb_manager.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>

namespace parcore {

// class ColumnChunkOutput {
// public:
//   ColumnChunkOutput(metadata::ColumnChunk column_chunk,
//                     libstf::OutputHandle output_handle);
//
//   const metadata::ColumnChunk &column_chunk() const;
//
//   const libstf::OutputHandle &output_handle() const;
//
// private:
//   metadata::ColumnChunk column_chunk_;
//   libstf::OutputHandle output_handle_;
// };

class Reader {
public:
  Reader(std::shared_ptr<coyote::cThread> cthread,
         std::shared_ptr<libstf::MemoryPool> memory_pool,
         std::shared_ptr<libstf::TLBManager> tlb_manager,
         std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
         ColumnChunkDecoderConfig column_chunk_config,
         PageDecoderConfig page_config, const metadata::Metadata &meta,
         libstf::stream_t decoder = 0);

  const metadata::Metadata &metadata() const;

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   */
  virtual void enqueue_column_chunk(size_t chunk, size_t column);

  /**
   * Returns whether there is a column chunk enqueued for processing. If this
   * function returns true, then the consumer can call `next_column_chunk` to
   * retrieve the output data, potentially blocking on until the acceleartor
   * is done processing.
   */
  virtual bool has_next_column_chunk();

  /**
   * Retrieves the next column chunk that has been enqueued for processing.
   */
  virtual std::shared_ptr<libstf::Buffer> next_column_chunk();

protected:
  std::shared_ptr<libstf::Buffer> allocate_buffer(size_t size);
  libstf::stream_mask_t decoder_mask() const;

  void enqueue_stream_input(const libstf::Buffer &buffer);

  // Sends a dictionary or data pge to be processed by the accelerator
  virtual void send_page(const metadata::Page &page, PageType page_type) = 0;

private:
  std::shared_ptr<coyote::cThread> cthread_;
  std::shared_ptr<libstf::MemoryPool> memory_pool_;
  std::shared_ptr<libstf::TLBManager> tlb_manager_;
  std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager_;

  ColumnChunkDecoderConfig column_chunk_config_;
  PageDecoderConfig page_config_;

  metadata::Metadata meta_;
  libstf::stream_t decoder_;

  std::queue<std::shared_ptr<libstf::OutputHandle>> queue_;
};

} // namespace parcore
