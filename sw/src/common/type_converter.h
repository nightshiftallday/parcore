#pragma once

#include "common.h"
#include "standalone_types.h"

namespace type_converter {

// Convert from parquet-dependent types to standalone types
inline standalone::page_info_compact convert_page_info(const common::page_info_compact& page) {
    standalone::page_info_compact standalone_page;
    standalone_page.type = page.type;
    standalone_page.uncompressed_page_size = page.uncompressed_page_size;
    standalone_page.compressed_page_size = page.compressed_page_size;
    standalone_page.num_values = page.num_values;
    standalone_page.header_size = page.header_size;
    standalone_page.encoding = page.encoding;
    standalone_page.compression = page.compression;
    standalone_page.isDefSet = page.isDefSet;
    standalone_page.isRefSet = page.isRefSet;
    standalone_page.byteWidth = page.byteWidth;
    standalone_page.fileOffset = page.fileOffset;
    return standalone_page;
}

inline standalone::column_chunk_info_compact convert_column_info(const common::column_chunk_info_compact& column) {
    standalone::column_chunk_info_compact standalone_column;
    standalone_column.pages.reserve(column.pages.size());
    for (const auto& page : column.pages) {
        standalone_column.pages.push_back(convert_page_info(page));
    }
    standalone_column.dictionary = column.dictionary;
    standalone_column.path_in_schema = column.path_in_schema;
    standalone_column.num_values = column.num_values;
    standalone_column.total_uncompressed_size = column.total_uncompressed_size;
    standalone_column.total_compressed_size = column.total_compressed_size;
    return standalone_column;
}

inline standalone::row_group_info_compact convert_row_group_info(const common::row_group_info_compact& row_group) {
    standalone::row_group_info_compact standalone_row_group;
    standalone_row_group.columns.reserve(row_group.columns.size());
    for (const auto& column : row_group.columns) {
        standalone_row_group.columns.push_back(convert_column_info(column));
    }
    return standalone_row_group;
}

// Convert vector of row groups
inline std::vector<standalone::row_group_info_compact> convert_row_groups(const std::vector<common::row_group_info_compact>& row_groups) {
    std::vector<standalone::row_group_info_compact> standalone_row_groups;
    standalone_row_groups.reserve(row_groups.size());
    for (const auto& row_group : row_groups) {
        standalone_row_groups.push_back(convert_row_group_info(row_group));
    }
    return standalone_row_groups;
}

} // namespace type_converter 