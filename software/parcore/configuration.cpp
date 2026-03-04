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

constexpr const uint32_t COLUMN_CHUNK_DECODER_COMPRESSION_ADDR = 0;
constexpr const uint32_t COLUMN_CHUNK_DECODER_NUM_VALUES_ADDR = 1;
constexpr const uint32_t COLUMN_CHUNK_DECODER_HYBRID_NUM_VALUES_ADDR = 2;
constexpr const uint32_t COLUMN_CHUNK_DECODER_TYP_ADDR = 3;

constexpr const uint32_t PAGE_DECODER_PAGE_TYPE_ADDR = 0;
constexpr const uint32_t PAGE_DECODER_NUM_VALUES_ADDR = 1;
constexpr const uint32_t PAGE_DECODER_LAST_ADDR = 2;

const std::string column_config_prefix = "parcore::ColumnChunkDecoderConfig::";

ColumnChunkDecoderConfig::ColumnChunkDecoderConfig(
    std::shared_ptr<coyote::cThread> cthread, uint32_t addr_offset,
    uint32_t num_regs)
    : Config(cthread, addr_offset, num_regs),
      num_decoders_(read_register(1).value()),
      maximum_num_enqueued_configs_(64 /* TODO: read from config */) {}

void ColumnChunkDecoderConfig::process_column_chunk(
    libstf::stream_t decoder, metadata::Compression compression,
    uint64_t num_values, uint64_t hybrid_num_values, libstf::type_t typ) {
  if (decoder >= num_decoders_) {
    throw std::runtime_error("attempted to configure ColumnChunkDecoder " +
                             std::to_string(decoder) +
                             " (zero-based numbering), out of " +
                             std::to_string(num_decoders_) + " decoders");
  }

  Profiler::open_regions({column_config_prefix + "process_column_chunk"});
  auto offset = decoder * COLUMN_CHUNK_DECODER_REGS;
  write_register(
      libstf::ConfigRegister(offset + COLUMN_CHUNK_DECODER_COMPRESSION_ADDR,
                             compression_to_hardware(compression)));
  write_register(libstf::ConfigRegister(
      offset + COLUMN_CHUNK_DECODER_NUM_VALUES_ADDR, num_values));
  write_register(libstf::ConfigRegister(
      offset + COLUMN_CHUNK_DECODER_HYBRID_NUM_VALUES_ADDR, hybrid_num_values));
  write_register(libstf::ConfigRegister(offset + COLUMN_CHUNK_DECODER_TYP_ADDR,
                                        static_cast<uint64_t>(typ)));
  Profiler::close_regions({column_config_prefix + "process_column_chunk"});
}

const libstf::stream_t ColumnChunkDecoderConfig::num_decoders() const {
  return num_decoders_;
}

const size_t ColumnChunkDecoderConfig::maximum_num_enqueued_configs() const {
  return maximum_num_enqueued_configs_;
}

inline uint64_t last_to_hardware(bool last) {
  if (last) {
    return 1;
  }

  return 0;
}

const std::string page_config_prefix = "parcore::PageDecoderConfig::";

PageDecoderConfig::PageDecoderConfig(std::shared_ptr<coyote::cThread> cthread,
                                     uint32_t addr_offset, uint32_t num_regs)
    : Config(cthread, addr_offset, num_regs),
      num_decoders_(read_register(1).value()),
      maximum_num_enqueued_configs_(64 /* TODO: read from config */) {}

void PageDecoderConfig::process_page(libstf::stream_t decoder,
                                     PageType page_type,
                                     metadata::Encoding encoding,
                                     uint64_t num_values, bool last) {
  if (decoder >= num_decoders_) {
    throw std::runtime_error("attempted to configure PageDecoder " +
                             std::to_string(decoder) +
                             " (zero-based numbering), out of " +
                             std::to_string(num_decoders_) + " decoders");
  }

  Profiler::open_regions({page_config_prefix + "process_page"});
  auto offset = decoder * PAGE_DECODER_REGS;
  auto hw_page_type = page_type_to_hardware(page_type, encoding);

  write_register(libstf::ConfigRegister(offset + PAGE_DECODER_PAGE_TYPE_ADDR,
                                        hw_page_type));
  write_register(libstf::ConfigRegister(offset + PAGE_DECODER_NUM_VALUES_ADDR,
                                        num_values));
  write_register(libstf::ConfigRegister(offset + PAGE_DECODER_LAST_ADDR,
                                        last_to_hardware(last)));
  Profiler::close_regions({page_config_prefix + "process_page"});
}

const libstf::stream_t PageDecoderConfig::num_decoders() const {
  return num_decoders_;
}

const size_t PageDecoderConfig::maximum_num_enqueued_configs() const {
  return maximum_num_enqueued_configs_;
}

} // namespace parcore
