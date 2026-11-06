#include <cstring>

#include <libstf/profiling.hpp>
#include <parcore/configuration.hpp>
#include <parcore/metadata/metadata.hpp>
#include <sstream>
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
    default: {
        std::ostringstream msg;
        msg << "Cannot convert compression scheme '" << compression
            << "' to hardware encoding: Only RAW (0) and SNAPPY (1) are supported by ParCore.";
        throw std::runtime_error(msg.str());
    }
    }
}

// column_chunk_conf_t packs (MSB -> LSB) as:
//   logical type_t [3 bits] | is_required [1 bit] | compression_t [1 bit] | num_values [32 bits] |
//   type_t [3 bits]
// The string_heap_addr [48 bits] does not fit alongside the rest in a single 64-bit AXIL write, so
// it travels in a second register that the hardware only pops for GERMAN_STR_T chunks.
constexpr const uint32_t COLUMN_CHUNK_DECODER_NUM_VALUES_SHIFT = 3;
constexpr const uint32_t COLUMN_CHUNK_DECODER_COMPRESSION_SHIFT =
    COLUMN_CHUNK_DECODER_NUM_VALUES_SHIFT + 32;
constexpr const uint32_t COLUMN_CHUNK_DECODER_IS_REQUIRED_SHIFT =
    COLUMN_CHUNK_DECODER_COMPRESSION_SHIFT + 1;
constexpr const uint32_t COLUMN_CHUNK_DECODER_LOGICAL_TYPE_SHIFT =
    COLUMN_CHUNK_DECODER_IS_REQUIRED_SHIFT + 1;

const std::string column_config_prefix = "parcore::ColumnChunkDecoderConfig::";

ColumnChunkDecoderConfig::ColumnChunkDecoderConfig(std::shared_ptr<coyote::cThread> cthread,
                                                   uint32_t addr_offset, uint32_t num_regs)
    : Config(cthread, addr_offset, num_regs), num_decoders_(read_register(1).value()),
      maximum_num_enqueued_configs_(read_register(2).value()) {}

// Casts the TypedNDataCasts in the ColumnChunkDecoder support
bool ColumnChunkDecoderConfig::supports_cast(libstf::type_t typ, libstf::type_t logical_typ) {
    const bool below_32 = logical_typ == libstf::type_t::INT16_T || logical_typ == libstf::type_t::BYTE_T;
    return logical_typ == typ || (typ == libstf::type_t::INT32_T && below_32) ||
           (typ == libstf::type_t::INT64_T && (logical_typ == libstf::type_t::INT32_T || below_32));
}

void ColumnChunkDecoderConfig::enqueue_column_chunk(libstf::stream_t      decoder,
                                                    metadata::Compression compression,
                                                    uint64_t num_values, libstf::type_t typ,
                                                    bool is_required, libstf::type_t logical_typ,
                                                    uint64_t string_heap_addr) {
    if (decoder >= num_decoders_) {
        throw std::runtime_error("attempted to configure ColumnChunkDecoder " +
                                 std::to_string(decoder) + " (zero-based numbering), out of " +
                                 std::to_string(num_decoders_) + " decoders");
    }
    if (!supports_cast(typ, logical_typ)) {
        std::ostringstream msg;
        msg << "ColumnChunkDecoder cannot cast " << typ << " to " << logical_typ;
        throw std::runtime_error(msg.str());
    }

    Profiler::open_regions({column_config_prefix + "enqueue_column_chunk"});
    uint64_t packed =
        ((static_cast<uint64_t>(logical_typ) & 0x7) << COLUMN_CHUNK_DECODER_LOGICAL_TYPE_SHIFT) |
        (static_cast<uint64_t>(is_required) << COLUMN_CHUNK_DECODER_IS_REQUIRED_SHIFT) |
        (compression_to_hardware(compression) << COLUMN_CHUNK_DECODER_COMPRESSION_SHIFT) |
        ((num_values & 0xFFFFFFFF) << COLUMN_CHUNK_DECODER_NUM_VALUES_SHIFT) |
        (static_cast<uint64_t>(typ) & 0x7);
    write_register(libstf::ConfigRegister(2 * decoder, packed));
    // Writing this for any other type would desynchronise the two config FIFOs, since
    // the hardware only pops it for GERMAN_STR_T.
    if (typ == metadata::GERMAN_STR_T)
        write_register(libstf::ConfigRegister(2 * decoder + 1, string_heap_addr));
    Profiler::close_regions({column_config_prefix + "enqueue_column_chunk"});
}

DecoderProfile ColumnChunkDecoderConfig::read_profile(libstf::stream_t decoder) {
    if (decoder >= num_decoders_) {
        throw std::runtime_error("Attempted to read profile of ColumnChunkDecoder " +
                                 std::to_string(decoder) + ", out of " +
                                 std::to_string(num_decoders_) + " decoders");
    }

    auto base = COLUMN_CHUNK_DECODER_INFO_REGS + decoder * COLUMN_CHUNK_DECODER_PROFILE_REGS;

    DecoderProfile profile;
    // Ascending order: the read of the last counter resets the profilers
    auto read_stream = [&](uint32_t offset) {
        StreamProfile stream;
        stream.handshakes_cycles = read_register(base + offset + 0).value();
        stream.starved_cycles    = read_register(base + offset + 1).value();
        stream.stalled_cycles    = read_register(base + offset + 2).value();
        stream.idle_cycles       = read_register(base + offset + 3).value();
        stream.last_handshakes   = read_register(base + offset + 4).value();
        return stream;
    };
    profile.in   = read_stream(0 * STREAM_PROFILE_REGS);
    profile.out  = read_stream(1 * STREAM_PROFILE_REGS);
    profile.heap = read_stream(2 * STREAM_PROFILE_REGS);
    profile.dict = read_stream(3 * STREAM_PROFILE_REGS);
    return profile;
}

const libstf::stream_t ColumnChunkDecoderConfig::num_decoders() const { return num_decoders_; }

const size_t ColumnChunkDecoderConfig::maximum_num_enqueued_configs() const {
    return maximum_num_enqueued_configs_;
}

} // namespace parcore
