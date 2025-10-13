#pragma once

#include <vector>
#include <string>
#include <cstdint>

// Standalone types for binary I/O - no parquet dependencies
namespace standalone {

// Compact page information structure
struct page_info_compact {
    int32_t type;
    int32_t uncompressed_page_size;
    int32_t compressed_page_size;
    int32_t num_values;
    int32_t header_size;
    int32_t encoding;
    int32_t compression;
    bool isDefSet;
    bool isRefSet;
    int32_t byteWidth;
    int64_t fileOffset;
    // Note: in_data and out_data are not serialized (pointers)
};

// Compact column chunk information structure
struct column_chunk_info_compact {
    std::vector<page_info_compact> pages;
    bool dictionary;
    std::vector<std::string> path_in_schema;
    
    int64_t num_values;
    int32_t byteWidth;  // Byte width for this column (same for all pages in the column)
    int32_t physical_type;  // Physical type of the column
    int32_t ordinal;  // Column ordinal within the row group
    
    // File offset information for page correlation
    int64_t file_offset;  // File offset where this column chunk starts
    int64_t file_size;    // Total size of this column chunk in the file
    
    // Compression and level information for pages
    int32_t compression;  // Compression codec used for this column
    bool has_def_levels;  // Whether this column has definition levels
    bool has_rep_levels;  // Whether this column has repetition levels
    
    int64_t total_uncompressed_size;
    int64_t total_compressed_size;
};

// Compact row group information structure
struct row_group_info_compact {
    std::vector<column_chunk_info_compact> columns;
    
    // Row group metadata
    int64_t num_rows;           // Number of rows in this row group
    int64_t total_byte_size;    // Total uncompressed byte size
    int64_t total_compressed_size; // Total compressed byte size
    int32_t ordinal;            // Row group ordinal
};

// Constants for page types
namespace page_types {
    const int32_t DATA_PAGE = 0;
    const int32_t DICTIONARY_PAGE = 2;
}

// Constants for encoding types
namespace encoding_types {
    const int32_t PLAIN = 0;
    const int32_t PLAIN_DICTIONARY = 2;
    const int32_t RLE = 3;
    const int32_t BIT_PACKED = 4;
    const int32_t DELTA_BINARY_PACKED = 5;
    const int32_t DELTA_LENGTH_BYTE_ARRAY = 6;
    const int32_t DELTA_BYTE_ARRAY = 7;
    const int32_t RLE_DICTIONARY = 8;
    const int32_t BYTE_STREAM_SPLIT = 9;
}

// Constants for compression types
namespace compression_types {
    const int32_t UNCOMPRESSED = 0;
    const int32_t SNAPPY = 1;
}

} // namespace standalone 