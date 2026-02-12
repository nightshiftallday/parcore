#include <cstring>

#include <libstf/profiling.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <stdexcept>
#include <string>

using libstf::Profiler;

namespace parcore {

std::ostream &operator<<(std::ostream &os, PageType page_type) {
  switch (page_type) {
  case PageType::DICT:
    return os << "DICT";
  case PageType::DATA:
    return os << "DATA";
  default:
    throw std::runtime_error("unexpected page type");
  }
}

enum class HardwarePageType : uint8_t {
  HYBRID = 0,
  DICT = 1,
  PLAIN = 2,
};

inline uint64_t page_type_to_hardware(PageType page_type,
                                      metadata::Encoding encoding) {
  HardwarePageType hw_page_type;
  switch (page_type) {
  case PageType::DICT:
    if (encoding != metadata::Encoding::PLAIN)
      throw std::runtime_error(
          "a PageType::DICT can only be encoded with Encoding::PLAIN");

    hw_page_type = HardwarePageType::DICT;
    break;

  case PageType::DATA:
    switch (encoding) {
    case metadata::Encoding::HYBRID:
      hw_page_type = HardwarePageType::HYBRID;
      break;

    case metadata::Encoding::PLAIN:
      hw_page_type = HardwarePageType::PLAIN;
      break;

    default:
      throw std::runtime_error("unexpected Encoding for data page");
    }
    break;

  default:
    throw std::runtime_error("unexpected PageType");
  }

  return static_cast<uint64_t>(hw_page_type);
}

inline uint64_t compression_to_hardware(metadata::Compression compression) {
  switch (compression) {
  case metadata::Compression::RAW:
    return 0;
  case metadata::Compression::SNAPPY:
    return 1;
  default:
    throw std::runtime_error(
        "Unexpected metadata compression to convert to hardware");
  }
}

constexpr const uint32_t PAGE_DECODER_COMPRESSION_ADDR = 0;
constexpr const uint32_t PAGE_DECODER_PAGE_TYPE_ADDR = 1;
constexpr const uint32_t PAGE_DECODER_NUM_VALUES_ADDR = 2;
constexpr const uint32_t PAGE_DECODER_TYP_ADDR = 3;

const std::string config_prefix = "parcore::PageDecoderConfig::";

PageDecoderConfig::PageDecoderConfig(std::shared_ptr<coyote::cThread> cthread,
                                     uint32_t addr_offset)
    : Config(cthread, addr_offset), num_decoders_(read_register(1).value()) {}

void PageDecoderConfig::process_page(libstf::stream_t decoder,
                                     metadata::Compression compression,
                                     PageType page_type,
                                     metadata::Encoding encoding,
                                     uint64_t num_values, libstf::type_t typ) {
  if (decoder >= num_decoders_) {
    throw std::runtime_error("attempted to configure decoder " +
                             std::to_string(decoder) +
                             " (zero-based numbering), out of " +
                             std::to_string(num_decoders_) + " decoders");
  }

  Profiler::open_regions({config_prefix + "process_page"});
  auto offset = decoder * PAGE_DECODER_REGS;
  auto hw_page_type = page_type_to_hardware(page_type, encoding);

  write_register(libstf::ConfigRegister(offset + PAGE_DECODER_COMPRESSION_ADDR,
                                        compression_to_hardware(compression)));
  write_register(libstf::ConfigRegister(offset + PAGE_DECODER_PAGE_TYPE_ADDR,
                                        hw_page_type));
  write_register(libstf::ConfigRegister(offset + PAGE_DECODER_NUM_VALUES_ADDR,
                                        num_values));
  write_register(libstf::ConfigRegister(offset + PAGE_DECODER_TYP_ADDR,
                                        static_cast<uint64_t>(typ)));
  Profiler::close_regions({config_prefix + "process_page"});
}

void PageDecoderConfig::process_chunk(libstf::stream_t decoder,
                                      metadata::ColumnChunk &column_chunk) {
  Profiler::open_regions({config_prefix + "process_chunk"});
  if (column_chunk.dictionary != std::nullopt) {
    process_page(decoder, column_chunk.compression, PageType::DICT,
                 column_chunk.dictionary->encoding, 0, column_chunk.type);
  }

  for (auto page : column_chunk.data) {
    process_page(decoder, column_chunk.compression, PageType::DATA,
                 page.encoding, page.num_values, column_chunk.type);
  }
  Profiler::close_regions({config_prefix + "process_chunk"});
}

const libstf::stream_t PageDecoderConfig::num_decoders() const {
  return num_decoders_;
}

} // namespace parcore
