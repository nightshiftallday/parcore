#pragma once

#include <memory>
#include <mutex>

#include <libstf/output_buffer_manager.hpp>
#include <libstf/output_handle.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>

namespace parcore {

class ColumnChunkDecoder
    : public std::enable_shared_from_this<ColumnChunkDecoder> {
public:
  ColumnChunkDecoder(
      std::shared_ptr<coyote::cThread> cthread,
      std::shared_ptr<libstf::TLBManager> tlb_manager,
      std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager,
      std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config,
      libstf::stream_t decoder);

  [[nodiscard]] const libstf::stream_t &decoder() const;

  struct Handle {
  public:
    Handle(std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder,
           std::unique_lock<std::mutex> lock,
           std::shared_ptr<libstf::OutputHandle> output_handle);

    void add_chunk(const std::shared_ptr<libstf::Buffer> &buffer);

    // The && qualifier means this can only be called on a moving handle
    std::shared_ptr<libstf::OutputHandle> done() &&;

  private:
    std::shared_ptr<ColumnChunkDecoder> column_chunk_decoder_;
    std::unique_lock<std::mutex> lock_;

    std::shared_ptr<libstf::OutputHandle> output_handle_;
    bool chunk_written_;
  };

  [[nodiscard]] std::unique_ptr<Handle>
  decode_column_chunk(const metadata::ColumnChunk &column_chunk);

  void
  finished_decoding_column_chunk(const metadata::ColumnChunk &column_chunk);

private:
  std::shared_ptr<coyote::cThread> cthread_;
  std::shared_ptr<libstf::TLBManager> tlb_manager_;
  std::shared_ptr<libstf::OutputBufferManager> output_buffer_manager_;
  std::shared_ptr<ColumnChunkDecoderConfig> column_chunk_config_;
  libstf::stream_t decoder_;

  std::mutex mtx;
  size_t column_chunk_enqueued_configs_;

  libstf::stream_mask_t decoder_mask() const;

  void enqueue_stream_input(const std::shared_ptr<libstf::Buffer> &buffer);
};

} // namespace parcore
