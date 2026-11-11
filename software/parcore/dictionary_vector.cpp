#include <parcore/dictionary_vector.hpp>

#include <algorithm>

namespace parcore {

uint32_t deferred_value_bytes(metadata::Type typ) {
    if (metadata::is_string_type(typ)) {
        return libstf::size_of(metadata::GERMAN_STR_T);
    }
    return libstf::size_of(metadata::to_libstf_type(typ));
}

std::optional<DeferredDictLayout> deferred_dict_layout(uint32_t value_bytes, uint64_t num_values,
                                                       uint64_t bytes_written) {
    if (value_bytes == 0) {
        return std::nullopt;
    }
    for (uint32_t index_bytes : {1u, 2u, 4u}) {
        const uint64_t indices_bytes = num_values * index_bytes;
        if (bytes_written < indices_bytes || (bytes_written - indices_bytes) % value_bytes != 0) {
            continue;
        }
        const uint64_t num_entries = (bytes_written - indices_bytes) / value_bytes;
        if (deferred_index_bytes(num_entries) == index_bytes) {
            return DeferredDictLayout{num_entries, value_bytes, index_bytes, num_values};
        }
    }
    return std::nullopt;
}

uint64_t max_deferred_output_bytes(uint32_t value_bytes, uint64_t num_values,
                                   uint64_t max_entries) {
    return max_entries * value_bytes + num_values * deferred_index_bytes(max_entries);
}

uint64_t max_deferred_dict_entries(const metadata::ColumnChunk &chunk) {
    uint64_t bound = chunk.num_values;
    if (chunk.total_uncompressed_size != 0) {
        // A PLAIN string entry is a 4 byte length prefix plus its bytes
        const uint64_t min_entry_bytes =
            metadata::is_string_type(chunk.type) ? 4 : deferred_value_bytes(chunk.type);
        bound = std::min(bound, chunk.total_uncompressed_size / min_entry_bytes);
    }
    return bound;
}

bool can_defer_dict_decoding(const metadata::ColumnChunk &chunk) {
    const bool supported_type =
        metadata::is_libstf_type(chunk.type) || metadata::is_string_type(chunk.type);
    return supported_type && chunk.is_dictionary_encoded && chunk.null_count.has_value() &&
           *chunk.null_count == 0 && chunk.num_values <= MAX_DEFERRED_DICT_ENTRIES;
}

} // namespace parcore
