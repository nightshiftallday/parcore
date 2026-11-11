#pragma once

#include <parcore/metadata/metadata.hpp>

#include <cstdint>
#include <optional>

namespace parcore {

/**
 * The output of a column chunk decoded with defer_dict_decoding (see
 * ColumnChunkDecoderConfig::enqueue_column_chunk) on the values stream:
 *
 *     [num_entries dictionary values][num_values indices]
 *
 * The values are the dictionary page's values in its order (german_str_t records for strings),
 * the indices are unsigned and little endian, 1 byte wide for up to 256 entries, 2 bytes for up to
 * 65,536 and 4 bytes above. The indices start right after the dictionary, which keeps them aligned
 * to their own width. The host does not know num_entries up front: it is in the dictionary page
 * header, which only the hardware parses. deferred_dict_layout() recovers it from the number of
 * bytes the decoder wrote.
 */
struct DeferredDictLayout {
    uint64_t num_entries;      // Dictionary entries
    uint32_t value_bytes;      // Bytes per dictionary value
    uint32_t index_bytes;      // Bytes per index
    uint64_t num_values;       // Indices, one per value of the chunk

    uint64_t dictionary_bytes() const { return num_entries * value_bytes; }
    uint64_t indices_offset() const { return dictionary_bytes(); }
    uint64_t indices_bytes() const { return num_values * index_bytes; }
    uint64_t total_bytes() const { return dictionary_bytes() + indices_bytes(); }
};

// The decoder's dictionary indices are 19 bits wide (ID_BITS in common.sv).
constexpr uint64_t MAX_DEFERRED_DICT_ENTRIES = uint64_t(1) << 19;

/**
 * The index width the decoder uses for a dictionary of num_entries entries. Mirrors index_type()
 * in column_chunk_decoder_core.sv.
 */
constexpr uint32_t deferred_index_bytes(uint64_t num_entries) {
    return num_entries <= 256 ? 1 : num_entries <= 65536 ? 2 : 4;
}

/**
 * Bytes per dictionary value of a deferred chunk of physical type typ: 16 for german strings,
 * otherwise the width of the physical type. Mirrors deferred_output_size() in
 * column_chunk_decoder_core.sv.
 */
uint32_t deferred_value_bytes(metadata::Type typ);

/**
 * The layout of a deferred chunk of num_values values whose decoder wrote bytes_written bytes on
 * its values stream. The size, value_bytes * num_entries + index_bytes(num_entries) * num_values,
 * strictly increases with num_entries, so at most one num_entries matches. nullopt if none does,
 * i.e. the output is not that of a deferred chunk of this shape.
 */
std::optional<DeferredDictLayout> deferred_dict_layout(uint32_t value_bytes, uint64_t num_values,
                                                       uint64_t bytes_written);

/**
 * The largest output of a deferred chunk whose dictionary has at most max_entries entries, to
 * size the output buffers before the decoder has seen the dictionary page.
 */
uint64_t max_deferred_output_bytes(uint32_t value_bytes, uint64_t num_values,
                                   uint64_t max_entries);

/**
 * An upper bound of the dictionary entries of a chunk from its metadata. A writer only adds the
 * values it encodes, so a dictionary has at most num_values entries, and every PLAIN encoded entry
 * takes at least value_bytes (4 bytes, the length prefix, for strings) of the chunk's uncompressed
 * bytes.
 */
uint64_t max_deferred_dict_entries(const metadata::ColumnChunk &chunk);

/**
 * Whether a chunk may be decoded with defer_dict_decoding. This assumes a DuckDB-written file:
 * DuckDB decides per column chunk between a dictionary page with only dictionary encoded data pages
 * and PLAIN, so a chunk whose encodings list a dictionary encoding has no PLAIN data page, which
 * would make the decoder hang. In addition, the chunk must have no NULLs (the indices are one per
 * non-NULL value, the decoder counts all values) and fit the decoder's 19 bit indices.
 */
bool can_defer_dict_decoding(const metadata::ColumnChunk &chunk);

} // namespace parcore
