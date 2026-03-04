#pragma once

#include <parcore/metadata/metadata.hpp>

#include <coyote/cThread.hpp>
#include <libstf/configuration.hpp>

namespace parcore {

constexpr const uint64_t COLUMN_CHUNK_DECODER_REGS = 4;
constexpr const uint64_t COLUMN_CHUNK_DECODER_CONFIG_ID = 0x5c19f934407065bd;

/**
 * Configues one or many hardware ColumnChunkDecoder module to properly process
 * the next page
 */
class ColumnChunkDecoderConfig : public libstf::Config {
public:
  ColumnChunkDecoderConfig(std::shared_ptr<coyote::cThread> cthread,
                           uint32_t addr_offset, uint32_t num_regs);

  /**
   * Configures the ColumnChunkDecoder to process the provided column chunk.
   * This just sets up the module, data will be configured and provided via the
   * PageDecoderConfig. This configuration oversees the decoding of multiple
   * pages (both dict and data) that belong to the same column chunk. Data from
   * all these pages will be returned in a single transfer normalized.
   *
   * @param decoder          The decoder to configure to process this chunk.
   * @param compression      Whether this chunk is SNAPPY compressed or not.
   * @param num_values       The total number of values contained in this chunk.
   * @param hybridnum_values The number of values produced by hybrid pages in
   *                         this chunk.
   * @param typ              The type of the values in the chunk.
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

enum class PageType : uint8_t { DICT, DATA };
std::ostream &operator<<(std::ostream &os, PageType page_type);

constexpr const uint64_t PAGE_DECODER_REGS = 3;
constexpr const uint64_t PAGE_DECODER_CONFIG_ID = 0xc0779792c320630e;

/**
 * Configues the decoding of a single Page through the ColumnCunkDecoder module.
 */
class PageDecoderConfig : public libstf::Config {
public:
  PageDecoderConfig(std::shared_ptr<coyote::cThread> cthread,
                    uint32_t addr_offset, uint32_t num_regs);

  /**
   * Configures the ColumnChunkDecoder with the appropriate parameters to
   * process the provided Page.
   *
   * @param decoder     The decoder to configure to process this page.
   * @param page_type   Whether this page contains a dictionary or data.
   * @param encoding    The encoding used to store the data in this page.
   * @param num_values  The number of values in the page we're parsing. Ignored
   *                    for dictionary pages.
   * @param last        Whether this is the last page in the column chunk.
   */
  void process_page(libstf::stream_t decoder, PageType page_type,
                    metadata::Encoding encoding, uint64_t num_values,
                    bool last);

  const libstf::stream_t num_decoders() const;
  const size_t maximum_num_enqueued_configs() const;

  static constexpr uint64_t ID = PAGE_DECODER_CONFIG_ID;

private:
  libstf::stream_t num_decoders_;
  size_t maximum_num_enqueued_configs_;
};

} // namespace parcore
