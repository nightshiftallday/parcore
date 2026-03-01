#pragma once

#include <memory>

#include <coyote/cThread.hpp>
#include <libstf/buffer.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/output_buffer_manager.hpp>
#include <libstf/tlb_manager.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>

namespace parcore {

namespace fpga {

class HardwareReader {
public:
  HardwareReader(
      std::shared_ptr<coyote::cThread> cthread,
      std::shared_ptr<libstf::MemoryPool> memory_pool,
      std::shared_ptr<libstf::TLBManager> tlb_manager,
      std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
      std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
      std::shared_ptr<PageDecoderConfig> page_config,
      const metadata::Metadata &meta, libstf::stream_t decoder = 0);

  [[nodiscard]] const metadata::Metadata &metadata() const;
  [[nodiscard]] const libstf::stream_t &decoder() const;

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   *
   * @param chunk      The index of the chunk to decode
   * @param column     The index of the column to decode
   * @param callback A callback function to be called when the column chunk is
   * done decoding.
   * @return The handle to receive the output from the hardware decoder.
   */
  [[nodiscard]] virtual std::shared_ptr<libstf::OutputHandle>
  decode_column_chunk(size_t chunk, size_t column);

protected:
  std::shared_ptr<libstf::Buffer> allocate_buffer(size_t size);
  libstf::stream_mask_t decoder_mask() const;

  void enqueue_stream_input(const libstf::Buffer &buffer);

  // Sends a dictionary or data pge to be processed by the accelerator
  virtual void send_page(const metadata::Page &page, PageType page_type) = 0;

  std::shared_ptr<coyote::cThread> cthread_;
  std::shared_ptr<libstf::MemoryPool> memory_pool_;
  std::shared_ptr<libstf::TLBManager> tlb_manager_;
  std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager_;

  std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config_;
  std::shared_ptr<PageDecoderConfig> page_config_;

  metadata::Metadata meta_;
  libstf::stream_t decoder_;
};

} // namespace fpga

} // namespace parcore
