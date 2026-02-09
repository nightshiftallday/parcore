#pragma once

#include <parcore/metadata/metadata.hpp>

#include <coyote/cThread.hpp>
#include <libstf/configuration.hpp>

namespace parcore {

enum class PageType : uint8_t { DICT, DATA };
std::ostream &operator<<(std::ostream &os, PageType page_type);

constexpr const uint64_t PAGE_DECODER_REGS = 4;
constexpr const uint64_t PAGE_DECODER_CONFIG_ID = 0xc0779792c320630e;

/**
 * Configues a hardware PageDecoder module to properly process the next page
 */
class PageDecoderConfig : public libstf::Config {
public:
  PageDecoderConfig(std::shared_ptr<coyote::cThread> cthread,
                    uint32_t addr_offset);

  /**
   * Configures the PageDecoder with the appropriate parameters to process the
   * provided Page.
   *
   * @param decoder     The decoder to configure to process this page.
   * @param compression The compression used for this page's data.
   * @param page_type   Whether this page contains a dictionary or data.
   * @param encoding    The encoding used to store the data in this page.
   * @param num_values  The number of values in the page we're parsing. Ignored
   *                    for dictionary pages.
   * @param typ         The type of the values stored in this page.
   */
  void process_page(libstf::stream_t decoder, metadata::Compression compression,
                    PageType page_type, metadata::Encoding encoding,
                    uint64_t num_values, libstf::type_t typ);

  /**
   * Configures the PageDecoder at most two times to process the two (or one)
   * pages present in the provided column chunk.
   *
   * @param decoder      The decoder to configure to process this chunk.
   * @param column_chunk The column chunk that shall be processed by the
   *                     PageDecoder.
   */
  void process_chunk(libstf::stream_t decoder,
                     metadata::ColumnChunk &column_chunk);

  const libstf::stream_t num_decoders() const;

  static constexpr uint64_t ID = PAGE_DECODER_CONFIG_ID;

private:
  libstf::stream_t num_decoders_;
};

} // namespace parcore
