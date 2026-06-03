#include <cstring>

#include <libstf/profiling.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <stdexcept>
#include <string>

using libstf::Profiler;

namespace parcore {

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
constexpr const uint32_t COLUMN_CHUNK_DECODER_TYP_ADDR = 2;

const std::string column_config_prefix = "parcore::ColumnChunkDecoderConfig::";

ColumnChunkDecoderConfig::ColumnChunkDecoderConfig(
    std::shared_ptr<coyote::cThread> cthread, uint32_t addr_offset,
    uint32_t num_regs)
    : Config(cthread, addr_offset, num_regs),
      num_decoders_(read_register(1).value()),
      maximum_num_enqueued_configs_(64 /* TODO: read from config */) {}

void ColumnChunkDecoderConfig::process_column_chunk(
    libstf::stream_t decoder, metadata::Compression compression,
    uint64_t num_values, libstf::type_t typ) {
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

} // namespace parcore
