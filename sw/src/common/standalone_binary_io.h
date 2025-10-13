#pragma once

#include "standalone_types.h"
#include <fstream>
#include <iostream>
#include <cstring>
#include <stdexcept>

namespace parquet_pageinfo {

// Simple binary writer for basic types
template<typename T>
void write_binary(std::ofstream& file, const T& value) {
    file.write(reinterpret_cast<const char*>(&value), sizeof(T));
}

// Simple binary reader for basic types
template<typename T>
void read_binary(std::ifstream& file, T& value) {
    file.read(reinterpret_cast<char*>(&value), sizeof(T));
}

// Write string with length prefix
void write_string(std::ofstream& file, const std::string& str) {
    uint32_t size = static_cast<uint32_t>(str.size());
    write_binary(file, size);
    file.write(str.c_str(), size);
}

// Read string with length prefix
void read_string(std::ifstream& file, std::string& str) {
    uint32_t size;
    read_binary(file, size);
    str.resize(size);
    file.read(&str[0], size);
}

// Write vector of strings
void write_string_vector(std::ofstream& file, const std::vector<std::string>& vec) {
    uint32_t size = static_cast<uint32_t>(vec.size());
    write_binary(file, size);
    for (const auto& str : vec) {
        write_string(file, str);
    }
}

// Read vector of strings
void read_string_vector(std::ifstream& file, std::vector<std::string>& vec) {
    uint32_t size;
    read_binary(file, size);
    vec.resize(size);
    for (auto& str : vec) {
        read_string(file, str);
    }
}

// Write page_info_compact
void write_page_info(std::ofstream& file, const standalone::page_info_compact& page) {
    write_binary(file, page.type);
    write_binary(file, page.uncompressed_page_size);
    write_binary(file, page.compressed_page_size);
    write_binary(file, page.num_values);
    write_binary(file, page.header_size);
    write_binary(file, page.encoding);
    write_binary(file, page.compression);
    write_binary(file, page.isDefSet);
    write_binary(file, page.isRefSet);
    write_binary(file, page.byteWidth);
    write_binary(file, page.fileOffset);
}

// Read page_info_compact
void read_page_info(std::ifstream& file, standalone::page_info_compact& page) {
    read_binary(file, page.type);
    read_binary(file, page.uncompressed_page_size);
    read_binary(file, page.compressed_page_size);
    read_binary(file, page.num_values);
    read_binary(file, page.header_size);
    read_binary(file, page.encoding);
    read_binary(file, page.compression);
    read_binary(file, page.isDefSet);
    read_binary(file, page.isRefSet);
    read_binary(file, page.byteWidth);
    read_binary(file, page.fileOffset);
}

// Write column_chunk_info_compact
void write_column_info(std::ofstream& file, const standalone::column_chunk_info_compact& column) {
    // Write pages vector
    uint32_t pages_size = static_cast<uint32_t>(column.pages.size());
    write_binary(file, pages_size);
    for (const auto& page : column.pages) {
        write_page_info(file, page);
    }
    
    write_binary(file, column.dictionary);
    write_string_vector(file, column.path_in_schema);
    write_binary(file, column.num_values);
    write_binary(file, column.byteWidth);
    write_binary(file, column.physical_type);
    write_binary(file, column.ordinal);
    write_binary(file, column.file_offset);
    write_binary(file, column.file_size);
    write_binary(file, column.compression);
    write_binary(file, column.has_def_levels);
    write_binary(file, column.has_rep_levels);
    write_binary(file, column.total_uncompressed_size);
    write_binary(file, column.total_compressed_size);
}

// Read column_chunk_info_compact
void read_column_info(std::ifstream& file, standalone::column_chunk_info_compact& column) {
    // Read pages vector
    uint32_t pages_size;
    read_binary(file, pages_size);
    column.pages.resize(pages_size);
    for (auto& page : column.pages) {
        read_page_info(file, page);
    }
    
    read_binary(file, column.dictionary);
    read_string_vector(file, column.path_in_schema);
    read_binary(file, column.num_values);
    read_binary(file, column.byteWidth);
    read_binary(file, column.physical_type);
    read_binary(file, column.ordinal);
    read_binary(file, column.file_offset);
    read_binary(file, column.file_size);
    read_binary(file, column.compression);
    read_binary(file, column.has_def_levels);
    read_binary(file, column.has_rep_levels);
    read_binary(file, column.total_uncompressed_size);
    read_binary(file, column.total_compressed_size);
}

// Write row_group_info_compact
void write_row_group_info(std::ofstream& file, const standalone::row_group_info_compact& row_group) {
    uint32_t columns_size = static_cast<uint32_t>(row_group.columns.size());
    write_binary(file, columns_size);
    for (const auto& column : row_group.columns) {
        write_column_info(file, column);
    }
    
    // Write row group metadata
    write_binary(file, row_group.num_rows);
    write_binary(file, row_group.total_byte_size);
    write_binary(file, row_group.total_compressed_size);
    write_binary(file, row_group.ordinal);
}

// Read row_group_info_compact
void read_row_group_info(std::ifstream& file, standalone::row_group_info_compact& row_group) {
    uint32_t columns_size;
    read_binary(file, columns_size);
    row_group.columns.resize(columns_size);
    for (auto& column : row_group.columns) {
        read_column_info(file, column);
    }
    
    // Read row group metadata
    read_binary(file, row_group.num_rows);
    read_binary(file, row_group.total_byte_size);
    read_binary(file, row_group.total_compressed_size);
    read_binary(file, row_group.ordinal);
}

// High-level save function
void save_row_groups_binary(const std::string& filename, const std::vector<standalone::row_group_info_compact>& row_groups) {
    std::ofstream file(filename, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open file for writing: " + filename);
    }
    
    // Write magic number and version
    const uint32_t magic = 0x50415251; // "PARQ"
    const uint32_t version = 1;
    write_binary(file, magic);
    write_binary(file, version);
    
    // Write number of row groups
    uint32_t num_groups = static_cast<uint32_t>(row_groups.size());
    write_binary(file, num_groups);
    
    // Write each row group
    for (const auto& row_group : row_groups) {
        write_row_group_info(file, row_group);
    }
    
    file.close();
}

// High-level load function
void load_row_groups_binary(const std::string& filename, std::vector<standalone::row_group_info_compact>& row_groups) {
    std::ifstream file(filename, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open file for reading: " + filename);
    }
    
    // Read and verify magic number
    uint32_t magic;
    read_binary(file, magic);
    if (magic != 0x50415251) {
        throw std::runtime_error("Invalid file format: " + filename);
    }
    
    // Read version
    uint32_t version;
    read_binary(file, version);
    if (version != 1) {
        throw std::runtime_error("Unsupported file version: " + std::to_string(version));
    }
    
    // Read number of row groups
    uint32_t num_groups;
    read_binary(file, num_groups);
    row_groups.resize(num_groups);
    
    // Read each row group
    for (auto& row_group : row_groups) {
        read_row_group_info(file, row_group);
    }
    
    file.close();
}

// Utility function to get string representation of page type
std::string get_page_type_string(int32_t type) {
    switch (type) {
        case standalone::page_types::DATA_PAGE: return "DATA_PAGE";
        case standalone::page_types::DICTIONARY_PAGE: return "DICTIONARY_PAGE";
        default: return "UNSUPPORTED";
    }
}

// Utility function to get string representation of encoding
std::string get_encoding_string(int32_t encoding) {
    switch (encoding) {
        case standalone::encoding_types::PLAIN: return "PLAIN";
        case standalone::encoding_types::PLAIN_DICTIONARY: return "PLAIN_DICTIONARY";
        case standalone::encoding_types::RLE: return "RLE";
        case standalone::encoding_types::BIT_PACKED: return "BIT_PACKED";
        case standalone::encoding_types::DELTA_BINARY_PACKED: return "DELTA_BINARY_PACKED";
        case standalone::encoding_types::DELTA_LENGTH_BYTE_ARRAY: return "DELTA_LENGTH_BYTE_ARRAY";
        case standalone::encoding_types::DELTA_BYTE_ARRAY: return "DELTA_BYTE_ARRAY";
        case standalone::encoding_types::RLE_DICTIONARY: return "RLE_DICTIONARY";
        case standalone::encoding_types::BYTE_STREAM_SPLIT: return "BYTE_STREAM_SPLIT";
        default: return "UNKNOWN";
    }
}

// Utility function to get string representation of compression
std::string get_compression_string(int32_t compression) {
    switch (compression) {
        case standalone::compression_types::UNCOMPRESSED: return "UNCOMPRESSED";
        case standalone::compression_types::SNAPPY: return "SNAPPY";
        default: return "UNSUPPORTED";
    }
}

} // namespace parquet_pageinfo 