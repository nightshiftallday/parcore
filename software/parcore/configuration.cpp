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
      maximum_num_enqueued_configs_(read_register(2).value()) {}

void ColumnChunkDecoderConfig::enqueue_column_chunk(
    libstf::stream_t decoder, metadata::Compression compression,
    uint64_t num_values, libstf::type_t typ) {
  if (decoder >= num_decoders_) {
    throw std::runtime_error("attempted to configure ColumnChunkDecoder " +
                             std::to_string(decoder) +
                             " (zero-based numbering), out of " +
                             std::to_string(num_decoders_) + " decoders");
  }

  Profiler::open_regions({column_config_prefix + "enqueue_column_chunk"});
  auto offset = decoder * COLUMN_CHUNK_DECODER_REGS;
  write_register(
      libstf::ConfigRegister(offset + COLUMN_CHUNK_DECODER_COMPRESSION_ADDR,
                             compression_to_hardware(compression)));
  write_register(libstf::ConfigRegister(
      offset + COLUMN_CHUNK_DECODER_NUM_VALUES_ADDR, num_values));
  write_register(libstf::ConfigRegister(offset + COLUMN_CHUNK_DECODER_TYP_ADDR,
                                        static_cast<uint64_t>(typ)));
  Profiler::close_regions({column_config_prefix + "enqueue_column_chunk"});
}

DecoderProfile ColumnChunkDecoderConfig::read_profile(libstf::stream_t decoder) {
  if (decoder >= num_decoders_) {
    throw std::runtime_error("Attempted to read profile of ColumnChunkDecoder " + 
                             std::to_string(decoder) + ", out of " + std::to_string(num_decoders_) + 
                             " decoders");
  }

  auto base = COLUMN_CHUNK_DECODER_INFO_REGS + decoder * COLUMN_CHUNK_DECODER_PROFILE_REGS;

  DecoderProfile profile;
  profile.in.handshakes_cycles = read_register(base + 0).value();
  profile.in.starved_cycles = read_register(base + 1).value();
  profile.in.stalled_cycles = read_register(base + 2).value();
  profile.in.idle_cycles = read_register(base + 3).value();
  profile.out.handshakes_cycles = read_register(base + 4).value();
  profile.out.starved_cycles = read_register(base + 5).value();
  profile.out.stalled_cycles = read_register(base + 6).value();
  profile.out.idle_cycles = read_register(base + 7).value();
  return profile;
}

const libstf::stream_t ColumnChunkDecoderConfig::num_decoders() const {
  return num_decoders_;
}

const size_t ColumnChunkDecoderConfig::maximum_num_enqueued_configs() const {
  return maximum_num_enqueued_configs_;
}

} // namespace parcore
