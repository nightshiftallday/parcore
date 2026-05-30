#pragma once

#include <parcore/metadata/metadata.hpp>

#include <coyote/cThread.hpp>
#include <libstf/configuration.hpp>

namespace parcore {

constexpr const uint64_t COLUMN_CHUNK_DECODER_REGS = 4;
constexpr const uint64_t COLUMN_CHUNK_DECODER_CONFIG_ID = 0x5c19f934407065bd;

class ColumnChunkDecoderConfig : public libstf::Config {
public:
  ColumnChunkDecoderConfig(std::shared_ptr<coyote::cThread> cthread,
                           uint32_t addr_offset, uint32_t num_regs);

  /**
   * Configures the ColumnChunkDecoder to process the provided column chunk.
   *
   * @param decoder     The decoder to configure.
   * @param compression Whether this chunk is SNAPPY compressed or not.
   * @param num_values  The total number of values in this chunk.
   * @param typ         The type of values in this chunk.
   */
  void process_column_chunk(libstf::stream_t decoder,
                            metadata::Compression compression,
                            uint64_t num_values, uint64_t hybrid_num_values,
                            libstf::type_t typ);

  const libstf::stream_t num_decoders() const;
  const size_t maximum_num_enqueued_configs() const;

  static constexpr uint64_t ID = COLUMN_CHUNK_DECODER_CONFIG_ID;

private:
  libstf::stream_t num_decoders_;
  size_t maximum_num_enqueued_configs_;
};

} // namespace parcore
