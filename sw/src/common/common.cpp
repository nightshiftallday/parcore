
#include "common.h"

#include "type_converter.h"
#include "standalone_binary_io.h"
#include <iomanip>  // For std::hex, std::setfill, std::setw
#include <cctype>   // For std::isprint
#include <filesystem>  // For std::filesystem::exists
#include <sstream>  // For std::ostringstream
#include <thread>   // For std::this_thread::sleep_for
#include <arrow/buffer.h>
#include <arrow/array/util.h>
#include <arrow/array/data.h>
#include <arrow/scalar.h>
#include <arrow/config.h>
#include <arrow/util/thread_pool.h>

// Helper function to determine byte width from Parquet physical type
// Throws std::runtime_error for unsupported types
int32_t getByteWidthFromPhysicalType(parquet::Type::type physical_type) {
    switch (physical_type) {
        case parquet::Type::BOOLEAN:
            return 1;  // 1 byte for boolean
        case parquet::Type::INT32:
            return 4;  // 4 bytes for int32
        case parquet::Type::INT64:
            return 8;  // 8 bytes for int64
        case parquet::Type::FLOAT:
            return 4;  // 4 bytes for float
        case parquet::Type::DOUBLE:
            return 8;  // 8 bytes for double
        case parquet::Type::INT96:
            throw std::runtime_error("Unsupported type: INT96 (deprecated)");
        case parquet::Type::BYTE_ARRAY:
            throw std::runtime_error("Unsupported type: BYTE_ARRAY (variable length)");
        case parquet::Type::FIXED_LEN_BYTE_ARRAY:
            throw std::runtime_error("Unsupported type: FIXED_LEN_BYTE_ARRAY");
        default:
            throw std::runtime_error("Unknown or unsupported Parquet type: " + std::to_string(static_cast<int>(physical_type)));
    }
}
// Helper function to get human-readable type name
std::string getTypeName(parquet::Type::type physical_type) {
    switch (physical_type) {
        case parquet::Type::BOOLEAN:
            return "BOOLEAN";
        case parquet::Type::INT32:
            return "INT32";
        case parquet::Type::INT64:
            return "INT64";
        case parquet::Type::FLOAT:
            return "FLOAT";
        case parquet::Type::DOUBLE:
            return "DOUBLE";
        case parquet::Type::INT96:
            return "INT96";
        case parquet::Type::BYTE_ARRAY:
            return "BYTE_ARRAY";
        case parquet::Type::FIXED_LEN_BYTE_ARRAY:
            return "FIXED_LEN_BYTE_ARRAY";
        default:
            return "UNKNOWN(" + std::to_string(static_cast<int>(physical_type)) + ")";
    }
}
bool hasParquetExtension(const std::string& filepath) {
    const std::string ext = ".parquet";
    if (filepath.length() < ext.length()) return false;

    std::string suffix = filepath.substr(filepath.length() - ext.length());
    
    // Make it lowercase to support case-insensitive match
    std::transform(suffix.begin(), suffix.end(), suffix.begin(), ::tolower);
    
    return suffix == ext;
}


std::string common::getPrintString(uint64_t val, std::unordered_map<uint64_t, std::string> map) {
    auto it = map.find(val);
    if (it != map.end()) {
        return it->second;
    } else {
        std::ostringstream oss;
        oss << "UNKNOWN (" << val << ")";
        return oss.str();
    }
}

void common::printBuffer(const void* buffer, size_t size, size_t byte_width, size_t values_per_line, 
    bool hex_output, size_t max_values, const std::string& mode, const std::string& endian, std::ostream& out, int32_t physical_type, bool use_formatting) {

    const uint8_t* bytes = reinterpret_cast<const uint8_t*>(buffer);
    bool is_little = (endian == "little");

    if (mode == "binary") {
        size_t total_values = std::min(size / byte_width, max_values);

        for (size_t i = 0; i < total_values; ++i) {
            size_t offset = i * byte_width;

            if (i % values_per_line == 0 && i != 0)
                out << '\n';

            size_t remaining = size - offset;
            size_t actual_width = std::min(byte_width, remaining);

            if (hex_output) {
                // Hex output - treat as raw bytes
                uint64_t value = 0;
                for (size_t k = 0; k < actual_width; ++k) {
                    size_t shift_index = is_little ? k : (actual_width - 1 - k);
                    value |= static_cast<uint64_t>(bytes[offset + k]) << (shift_index * 8);
                }
                out << "0x" << std::setw(byte_width * 2) << std::setfill('0') << std::hex << value << " ";
            } else {
                // Value output - interpret based on physical type
                if (actual_width == byte_width) {
                    if (physical_type == static_cast<int32_t>(parquet::Type::BOOLEAN)) {
                        bool value = bytes[offset] != 0;
                        if (use_formatting) {
                            out << std::setw(8) << std::setfill(' ') << (value ? "true" : "false") << " ";
                        } else {
                            out << (value ? "true" : "false") << " ";
                        }
                    } else if (physical_type == static_cast<int32_t>(parquet::Type::INT32)) {
                        int32_t value = 0;
                        for (size_t k = 0; k < 4; ++k) {
                            size_t shift_index = is_little ? k : (3 - k);
                            value |= static_cast<int32_t>(bytes[offset + k]) << (shift_index * 8);
                        }
                        if (use_formatting) {
                            out << std::setw(12) << std::setfill(' ') << value << " ";
                        } else {
                            out << value << " ";
                        }
                    } else if (physical_type == static_cast<int32_t>(parquet::Type::INT64)) {
                        int64_t value = 0;
                        for (size_t k = 0; k < 8; ++k) {
                            size_t shift_index = is_little ? k : (7 - k);
                            value |= static_cast<int64_t>(bytes[offset + k]) << (shift_index * 8);
                        }
                        if (use_formatting) {
                            out << std::setw(20) << std::setfill(' ') << value << " ";
                        } else {
                            out << value << " ";
                        }
                    } else if (physical_type == static_cast<int32_t>(parquet::Type::FLOAT)) {
                        uint32_t raw_value = 0;
                        for (size_t k = 0; k < 4; ++k) {
                            size_t shift_index = is_little ? k : (3 - k);
                            raw_value |= static_cast<uint32_t>(bytes[offset + k]) << (shift_index * 8);
                        }
                        float value = *reinterpret_cast<float*>(&raw_value);
                        if (use_formatting) {
                            out << std::setw(15) << std::setfill(' ') << std::fixed << std::setprecision(6) << value << " ";
                        } else {
                            out << std::fixed << value << " ";
                        }
                    } else if (physical_type == static_cast<int32_t>(parquet::Type::DOUBLE)) {
                        uint64_t raw_value = 0;
                        for (size_t k = 0; k < 8; ++k) {
                            size_t shift_index = is_little ? k : (7 - k);
                            raw_value |= static_cast<uint64_t>(bytes[offset + k]) << (shift_index * 8);
                        }
                        double value = *reinterpret_cast<double*>(&raw_value);
                        if (use_formatting) {
                            out << std::setw(20) << std::setfill(' ') << std::fixed << std::setprecision(10) << value << " ";
                        } else {
                            out << std::fixed << value << " ";
                        }
                    } else {
                        // Fallback to raw decimal
                        uint64_t value = 0;
                        for (size_t k = 0; k < actual_width; ++k) {
                            size_t shift_index = is_little ? k : (actual_width - 1 - k);
                            value |= static_cast<uint64_t>(bytes[offset + k]) << (shift_index * 8);
                        }
                        if (use_formatting) {
                            out << std::setw(byte_width * 3) << std::setfill(' ') << std::dec << value << " ";
                        } else {
                            out << std::dec << value << " ";
                        }
                    }
                } else {
                    // Incomplete value - show as hex
                    out << "0x";
                    for (size_t k = 0; k < actual_width; ++k) {
                        out << std::setw(2) << std::setfill('0') << std::hex << static_cast<int>(bytes[offset + k]);
                    }
                    if (use_formatting) {
                        out << std::setw((byte_width - actual_width) * 2) << std::setfill(' ') << " ";
                    } else {
                        out << " ";
                    }
                }
            }
        }

        out << std::dec << std::endl;

    } else if (mode == "string") {
        size_t count = 0;
        size_t i = 0;

        while (i < size && count < max_values) {
            const char* str = reinterpret_cast<const char*>(bytes + i);
            size_t remaining = size - i;

            size_t len = strnlen(str, remaining);
            std::string line(str, len);
            out << line << '\n';

            i += len + 1;
            ++count;
        }
    } else {
        out << "Unknown mode: " << mode << std::endl;
    }
}
void common::printBufferHex(const void* buffer, size_t size, size_t bytesPerValue) {
    const uint8_t* data = static_cast<const uint8_t*>(buffer);

    for (size_t i = 0; i < size; i += bytesPerValue) {
        uint64_t value = 0;

        // Combine bytes into a single integer value (big endian)
        for (size_t j = 0; j < bytesPerValue && (i + j) < size; ++j) {
            value |= static_cast<uint64_t>(data[i + j]) << (8 * j);
        }

        DEBUG_OUT << "0x"
                  << std::setw(bytesPerValue * 2)
                  << std::setfill('0')
                  << std::hex
                  << value
                  << ", ";
    }

    
}



std::unique_ptr<parquet::arrow::FileReader> common::prepareArrowTableReader(std::string filePath){
    // Check if file exists first
    if (!std::filesystem::exists(filePath)) {
        throw std::runtime_error("File does not exist: " + filePath);
    }
    
    DBG_1("Opening file: " << filePath);
    
    // Try the direct approach first - open file stream then create parquet reader
    try {
        auto file_result = arrow::io::ReadableFile::Open(filePath, arrow::default_memory_pool());
        if (!file_result.ok()) {
            DBG_WARN("Direct file stream opening failed: " << file_result.status().ToString());
            DBG_1("Falling back to memory buffer approach...");
        } else {
            auto parquet_reader_result = parquet::arrow::OpenFile(file_result.ValueOrDie(), arrow::default_memory_pool());
            if (!parquet_reader_result.ok()) {
                DBG_WARN("Direct parquet opening failed: " << parquet_reader_result.status().ToString());
                DBG_1("Falling back to memory buffer approach...");
            } else {
                DBG_1("Direct file opening succeeded");
                return std::move(parquet_reader_result).ValueOrDie();
            }
        }
    } catch (const std::exception& e) {
        DBG_WARN("Direct file opening threw exception: " << e.what());
        DBG_1("Falling back to memory buffer approach...");
    }
    
    // Fallback to the memory buffer approach
    // Open the file with proper error checking
    auto file_result = arrow::io::ReadableFile::Open(filePath, arrow::default_memory_pool());
    if (!file_result.ok()) {
        throw std::runtime_error("Failed to open file: " + filePath + " - " + file_result.status().ToString());
    }
    std::shared_ptr<arrow::io::ReadableFile> file = file_result.ValueOrDie();
    
    // Get file size with error checking
    auto file_size_result = file->GetSize();
    if (!file_size_result.ok()) {
        throw std::runtime_error("Failed to get file size for: " + filePath + " - " + file_size_result.status().ToString());
    }
    auto file_size = file_size_result.ValueOrDie();
    
    DBG_1("File size: " << file_size << " bytes");
    
    // Read file data with error checking
    std::vector<uint8_t> file_data(file_size);
    auto read_result = file->Read(file_size, file_data.data());
    if (!read_result.ok()) {
        throw std::runtime_error("Failed to read file data from: " + filePath + " - " + read_result.status().ToString());
    }
    
    DBG_1("File data read successfully, creating buffer reader");
    
    // Create buffer and buffer reader
    auto buffer = std::make_shared<arrow::Buffer>(file_data.data(), file_size);
    auto buffer_reader = std::make_shared<arrow::io::BufferReader>(buffer);
    
    // Open parquet file with error checking
    auto parquet_reader_result = parquet::arrow::OpenFile(buffer_reader, arrow::default_memory_pool());
    if (!parquet_reader_result.ok()) {
        throw std::runtime_error("Failed to open parquet file: " + filePath + " - " + parquet_reader_result.status().ToString());
    }
    
    DBG_1("Parquet reader created successfully");
    return std::move(parquet_reader_result).ValueOrDie();
}

std::vector<struct common::row_group_info_compact> common::analyseParquetFile(std::string filename, std::ostream& debug_out) {
    if (!hasParquetExtension(filename)) {
        std::cerr << "File is not a parquet file" << std::endl;
        return {};
    }

    std::unique_ptr<parquet::ParquetFileReader> reader = parquet::ParquetFileReader::OpenFile(filename, false);
    std::shared_ptr<parquet::FileMetaData> metadata = reader->metadata();
    
    // Check Parquet format version - this is crucial for compatibility
    auto created_by = metadata->created_by();
    auto version = metadata->version();
    debug_out << "Parquet file created by: " << created_by << std::endl;
    debug_out << "Parquet format version: " << version << std::endl;
    
    // Add assert to catch version mismatches
    if (version != parquet::ParquetVersion::PARQUET_2_6) {
        debug_out << "WARNING: Unexpected Parquet version: " << version << std::endl;
        debug_out << "This might cause page header parsing issues!" << std::endl;
    }
    
    uint32_t num_row_groups = metadata->num_row_groups();
    uint64_t num_rows = metadata->num_rows();
    uint32_t num_columns = metadata->num_columns();
    auto schema = metadata->schema();
    debug_out << "Analyzing: " << num_columns << " columns, " << num_rows << " rows, " << num_row_groups << " row groups" << std::endl;

    // Open binary Parquet file, read size and content into char array
    std::ifstream file(filename, std::ios::ate | std::ios::binary);
    if (!file) {
        std::cerr << "Cannot open file " << filename << std::endl;
        return {};
    }
    std::streampos file_size = file.tellg();
    file.seekg(0, std::ios::beg);
    char *file_data = (char *) malloc(file_size);
    file.read(file_data, file_size);
    debug_out << "File loaded: " << file_size << " bytes" << std::endl;

#ifdef DEBUG_3
    // Print hex dump of file beginning
    const size_t max_hex_bytes = 512; // Maximum bytes to show in hex dump
    const size_t bytes_per_line = 32;
    size_t hex_bytes_to_show = std::min(static_cast<size_t>(file_size), max_hex_bytes);
    
    debug_out << "File hex dump (first " << hex_bytes_to_show << " bytes):" << std::endl;
    for (size_t offset = 0; offset < hex_bytes_to_show; offset += bytes_per_line) {
        // Print offset
        debug_out << std::hex << std::setfill('0') << std::setw(8) << offset << ": ";
        
        // Print hex bytes
        size_t line_bytes = std::min(bytes_per_line, hex_bytes_to_show - offset);
        for (size_t i = 0; i < line_bytes; i++) {
            debug_out << std::hex << std::setfill('0') << std::setw(2) 
                     << (static_cast<unsigned char>(file_data[offset + i]) & 0xFF) << " ";
        }
        
        // Pad with spaces if line is shorter
        for (size_t i = line_bytes; i < bytes_per_line; i++) {
            debug_out << "   ";
        }
        
        // Print ASCII representation
        debug_out << " |";
        for (size_t i = 0; i < line_bytes; i++) {
            unsigned char c = static_cast<unsigned char>(file_data[offset + i]);
            debug_out << (std::isprint(c) ? static_cast<char>(c) : '.');
        }
        debug_out << "|" << std::endl;
    }
    debug_out << std::dec << std::endl; // Reset to decimal output
#endif

    // MAIN START
    std::vector<struct common::row_group_info_compact> row_groups(num_row_groups);
    
    // STEP 1: Parse footer metadata and create row group and column info structures
    debug_out << "Step 1: Parsing footer metadata..." << std::endl;
    
    for (auto& rg : row_groups) {
        rg.columns.resize(num_columns);
    }

    for (uint32_t i = 0; i < num_row_groups; i++) {
        row_groups[i].num_rows = metadata->RowGroup(i)->num_rows();
        row_groups[i].total_byte_size = metadata->RowGroup(i)->total_byte_size();
        row_groups[i].total_compressed_size = metadata->RowGroup(i)->total_compressed_size();
        row_groups[i].ordinal = i;

        debug_out << "Row group " << i << ": " << row_groups[i].num_rows << " rows, " 
                 << row_groups[i].total_byte_size << " bytes uncompressed, " 
                 << row_groups[i].total_compressed_size << " bytes compressed" << std::endl;
        debug_out << "  Row group total compressed size: " << row_groups[i].total_compressed_size << " bytes ( Offset to first page: " << metadata->RowGroup(i)->file_offset() << ")" << std::endl;

        for (uint32_t c = 0; c < num_columns; c++) {
            debug_out << std::endl;
            auto column = metadata->RowGroup(i)->ColumnChunk(c);
            auto compression = common::ToParquetCompressionCodec(column->compression());

            auto column_descriptor = schema->Column(c);
            auto physical_type = column_descriptor->physical_type();
            int32_t column_byte_width = getByteWidthFromPhysicalType(physical_type);
            bool has_def_levels = column_descriptor->max_definition_level() > 0;
            bool has_rep_levels = column_descriptor->max_repetition_level() > 0;


            row_groups[i].columns[c].path_in_schema = column->path_in_schema()->ToDotVector();
            row_groups[i].columns[c].num_values = column->num_values();
            row_groups[i].columns[c].total_uncompressed_size = column->total_uncompressed_size();
            row_groups[i].columns[c].total_compressed_size = column->total_compressed_size();
            row_groups[i].columns[c].dictionary = column->has_dictionary_page();
            row_groups[i].columns[c].byteWidth = column_byte_width;
            row_groups[i].columns[c].arrow_type = common::parquetTypeToArrowType(physical_type);
            row_groups[i].columns[c].physical_type = static_cast<int32_t>(physical_type);
            row_groups[i].columns[c].ordinal = c;
            row_groups[i].columns[c].compression = static_cast<int32_t>(compression);
            row_groups[i].columns[c].has_def_levels = has_def_levels;
            row_groups[i].columns[c].has_rep_levels = has_rep_levels;
            
            // Initialize output buffer fields (will be set later during FPGA processing)
            row_groups[i].columns[c].output_buffer = nullptr;
            row_groups[i].columns[c].output_size = 0;

            // Store file offset information for page correlation
            // Note: We'll calculate actual sequential offsets after finding the data start position
            int64_t data_offset = column->data_page_offset();
            int64_t dict_offset = column->has_dictionary_page() ? column->dictionary_page_offset() : data_offset;
            int64_t start_offset = (dict_offset < data_offset) ? dict_offset : data_offset;
            
            row_groups[i].columns[c].file_offset = start_offset; // Temporarily store metadata offset
            row_groups[i].columns[c].file_size = column->total_compressed_size();
            
            // Validate that the calculated offset makes sense
            if (start_offset < 0) {
                debug_out << "    WARNING: Negative file offset: " << start_offset << std::endl;
            }
            if (start_offset + column->total_compressed_size() > file_size) {
                debug_out << "    WARNING: Column extends beyond file size: offset " << start_offset 
                         << " + size " << column->total_compressed_size() << " > " << file_size << std::endl;
            }            
            
            debug_out << "  Column " << c << " (" << getTypeName(physical_type) << "): " 
                     << column->num_values() << " values, " 
                     << column->total_uncompressed_size() << " bytes uncompressed, "
                     << column->total_compressed_size() << " bytes compressed, "
                     << "file offset " << row_groups[i].columns[c].file_offset << ", "
                     << "byte width " << column_byte_width;
            if (column->has_dictionary_page()) {
                debug_out << ", has dictionary";
            }
            debug_out << std::endl;

            // Read pages sequentially until failure, then continue with next column
            int j = row_groups[i].columns[c].file_offset;
            int column_start = j;
            debug_out << "    Page reading starts at offset " << j << std::endl;

            parquet_thrift::format::PageHeader page_header;
            int32_t header_size;
            for (; j < file_size && j - column_start < row_groups[i].columns[c].file_size; ) {
                try {
                    auto buf = std::make_shared<apache::thrift::transport::TMemoryBuffer>(
                        reinterpret_cast<uint8_t *>(file_data + j), file_size);
                    size_t before = buf->available_read();
        
                    apache::thrift::protocol::TCompactProtocol protocol(buf);
                    page_header.read(&protocol);
        
                    size_t after = buf->available_read();
                    header_size = before - after;
                    j += header_size;

                    debug_out << "    Header read successfully: size=" << header_size 
                    << ", type=" << page_header.type 
                    << ", compressed_size=" << page_header.compressed_page_size 
                    << ", from " << j - header_size << " to " << (j + page_header.compressed_page_size) << std::endl;
                } catch (const apache::thrift::TException& e) {
                    debug_out << "    No more headers found at offset " << j << std::endl;                
                    break; // No header
                }

                // Check page type and handle accordingly
                if (page_header.type == parquet_thrift::format::PageType::INDEX_PAGE) {
                    debug_out << "  Skipping INDEX_PAGE at offset " << j << std::endl;
                    j += page_header.compressed_page_size;
                    continue;
                }
                if (page_header.type == parquet_thrift::format::PageType::DATA_PAGE_V2) {
                    std::string error_msg = "DATA_PAGE_V2 is not supported at offset " + std::to_string(j);
                    debug_out << "Error: " << error_msg << std::endl;
                    throw std::runtime_error(error_msg);
                }

                // Create page info
                int32_t num_values = (page_header.type == parquet_thrift::format::PageType::DATA_PAGE) 
                    ? page_header.data_page_header.num_values 
                    : page_header.dictionary_page_header.num_values;
                auto encoding = (page_header.type == parquet_thrift::format::PageType::DATA_PAGE) 
                    ? page_header.data_page_header.encoding 
                    : page_header.dictionary_page_header.encoding;
                
                struct common::page_info_compact page = {
                    static_cast<int32_t>(page_header.type), 
                    page_header.uncompressed_page_size, 
                    page_header.compressed_page_size,
                    num_values, 
                    header_size, 
                    static_cast<int32_t>(encoding), 
                    row_groups[i].columns[c].compression, // Use stored compression
                    row_groups[i].columns[c].has_def_levels, // Use stored def levels
                    row_groups[i].columns[c].has_rep_levels, // Use stored rep levels
                    row_groups[i].columns[c].byteWidth, 
                    static_cast<int64_t>(j - header_size) // Points to beginning of page (including header)
                };
                
                row_groups[i].columns[c].pages.push_back(page);
                
                debug_out << "  Page " << row_groups[i].columns[c].pages.size() << " assigned to row group " << i 
                        << ", column " << c << ": type=" << page_header.type 
                        << ", size=" << page_header.compressed_page_size 
                        << ", header=" << header_size 
                        << ", offset=" << j << std::endl;
                j += page_header.compressed_page_size;
                
            } // End of page reading loop

        } // End of column reading loop
    } // End of row group reading loop
        
    reader->Close();
    file.close();
    free(file_data);

    return row_groups;
}


// Store the analysis in a text file and binary file. Outdated
void common::analyseParquetFileToFile(std::string filepath) {
    if (!hasParquetExtension(filepath)) {
        std::cerr << "File is not a parquet file" << std::endl;
        return;
    }
    
    // Write text output
    std::string output_filename = filepath.substr(0, filepath.length() - 8) + "_pages.txt";
    std::ofstream output_file(output_filename);
    if (!output_file.is_open()) {
        std::cerr << "Error opening file for writing: " << output_filename << std::endl;
        return;
    }
    
    // Use the improved analyseParquetFile function with file output
    std::vector<struct common::row_group_info_compact> row_groups = analyseParquetFile(filepath, output_file);
    
    if (row_groups.empty()) {
        std::cerr << "Failed to analyze parquet file" << std::endl;
        return;
    }



    // Write row groups information to the output file
    output_file << "=== ROW GROUPS ANALYSIS ===" << std::endl;
    output_file << std::endl;

    for (size_t i = 0; i < row_groups.size(); i++) {
        output_file << "Row Group " << i << ":" << std::endl;
        output_file << "  Rows: " << row_groups[i].num_rows << std::endl;
        output_file << "  Total Byte Size: " << row_groups[i].total_byte_size << " bytes" << std::endl;
        output_file << "  Total Compressed Size: " << row_groups[i].total_compressed_size << " bytes" << std::endl;
        output_file << "  Ordinal: " << row_groups[i].ordinal << std::endl;
        output_file << "  Columns: " << row_groups[i].columns.size() << std::endl;
        output_file << std::endl;
        
        for (size_t c = 0; c < row_groups[i].columns.size(); c++) {
            const auto& column = row_groups[i].columns[c];
            output_file << "  Column " << c << ":" << std::endl;
            output_file << "    Path: ";
            for (size_t p = 0; p < column.path_in_schema.size(); p++) {
                if (p > 0) output_file << ".";
                output_file << column.path_in_schema[p];
            }
            output_file << std::endl;
            output_file << "    Physical Type: " << column.physical_type << std::endl;
            output_file << "    Ordinal: " << column.ordinal << std::endl;
            output_file << "    Dictionary: " << (column.dictionary ? "Yes" : "No") << std::endl;
            output_file << "    Num Values: " << column.num_values << std::endl;
            output_file << "    Total Uncompressed Size: " << column.total_uncompressed_size << " bytes" << std::endl;
            output_file << "    Total Compressed Size: " << column.total_compressed_size << " bytes" << std::endl;
            output_file << "    Compression Ratio: " << std::fixed << std::setprecision(2) 
                       << (column.total_uncompressed_size > 0 ? 
                           (1.0 - (double)column.total_compressed_size / column.total_uncompressed_size) * 100.0 : 0.0)
                       << "%" << std::endl;
            output_file << "    Byte Width: " << column.byteWidth << " bytes" << std::endl;
            output_file << "    Compression: " << column.compression << std::endl;
            output_file << "    Has Definition Levels: " << (column.has_def_levels ? "Yes" : "No") << std::endl;
            output_file << "    Has Repetition Levels: " << (column.has_rep_levels ? "Yes" : "No") << std::endl;
            output_file << "    File Offset: " << column.file_offset << std::endl;
            output_file << "    File Size: " << column.file_size << " bytes" << std::endl;
            output_file << "    Pages: " << column.pages.size() << std::endl;
            
            for (size_t p = 0; p < column.pages.size(); p++) {
                const auto& page = column.pages[p];
                output_file << "      Page " << p << ":" << std::endl;
                output_file << "        Type: " << (page.type == 0 ? "DATA_PAGE" : 
                                                   page.type == 2 ? "DICTIONARY_PAGE" : "UNSUPPORTED") << std::endl;
                output_file << "        Num Values: " << page.num_values << std::endl;
                output_file << "        Uncompressed Size: " << page.uncompressed_page_size << " bytes" << std::endl;
                output_file << "        Compressed Size: " << page.compressed_page_size << " bytes" << std::endl;
                output_file << "        Header Size: " << page.header_size << " bytes" << std::endl;
                output_file << "        File Offset: " << page.fileOffset << std::endl;
                output_file << "        Encoding: " << page.encoding << std::endl;
                output_file << "        Compression: " << page.compression << std::endl;
                output_file << "        Has Definition Levels: " << (page.isDefSet ? "Yes" : "No") << std::endl;
                output_file << "        Has Repetition Levels: " << (page.isRefSet ? "Yes" : "No") << std::endl;
                output_file << "        Byte Width: " << page.byteWidth << std::endl;
            }
            output_file << std::endl;
        }
        output_file << std::endl;
    }
    
    output_file.close();
    DEBUG_OUT << "Analysis written to: " << output_filename << std::endl;
    
    // Also save binary version for easy loading (standalone format)
    std::string binary_filename = filepath.substr(0, filepath.length() - 8) + "_pages.bin";
    try {
        // Convert to standalone types and save
        auto standalone_row_groups = type_converter::convert_row_groups(row_groups);
        parquet_pageinfo::save_row_groups_binary(binary_filename, standalone_row_groups);
        DEBUG_OUT << "Binary data written to: " << binary_filename << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Warning: Could not save binary file: " << e.what() << std::endl;
    }
}



// Generate 64 bit config packet for FPGA
int64_t common::generateConfig(common::page_info_compact* page, bool setResetBit, bool jump_header, bool simulate_compression){
    uint64_t config = 0;
    uint64_t masked_value = 0;

    // Send 32 bit num_values or 16 bit header_size
    if (!jump_header) assert(page->header_size <= 65535 && "Header size must be fit in 16 bits");
    if (jump_header) assert(page->num_values <= 4294967295 && "Num values must be fit in 32 bits");
    uint64_t mask = ((1ULL << 32) - 1) << 16; // Num_values
    config &= ~mask; 
    int64_t value = static_cast<int64_t>(jump_header ? page->num_values : page->header_size);
    config |= (value << 16);

    mask = ((1ULL << 4) - 1) << 12; // ByteWidth
    config &= ~mask;
    masked_value = static_cast<uint64_t>(page->byteWidth & ((1U << 4) - 1));
    config = (config & ~mask) | (masked_value << 12);

    mask = ((1ULL << 4) - 1) << 8; // Encoding
    config &= ~mask;
    masked_value = static_cast<uint64_t>(page->encoding & ((1U << 4) - 1));
    config = (config & ~mask) | (masked_value << 8);

    mask = ((1ULL << 3) - 1) << 5; // Compression
    config &= ~mask;
    masked_value = static_cast<uint64_t>((simulate_compression ? 2ULL : page->compression) & ((1U << 3) - 1));
    config = (config & ~mask) | (masked_value << 5);

    mask = 1ULL << 4; // is_def_set
    config &= ~mask;
    masked_value = static_cast<uint64_t>(page->isDefSet);
    config = (config & ~mask) | (masked_value << 4);

    mask = 1ULL << 3; // is_ref_set
    config &= ~mask;
    masked_value = static_cast<uint64_t>(page->isRefSet);
    config = (config & ~mask) | (masked_value << 3);

    mask = ((1ULL << 2) - 1) << 1; // pageType
    config &= ~mask;
    masked_value = static_cast<uint64_t>(page->type & ((1U << 2) - 1));
    config = (config & ~mask) | (masked_value << 1);

    mask = 1ULL; // reset_bit
    config &= ~mask;
    masked_value = setResetBit ? 1ULL : 0ULL;
    config = (config & ~mask) | (masked_value);
    return config;
}

// Ready small input and output memory buffers for FPGA
void common::readyMemoryBuffers(coyote::cThread* cthread, common::page_info_compact* page, char *file_data, size_t file_size, bool jump_header){
    uint32_t in_size = jump_header ? page->compressed_page_size : page->compressed_page_size + page->header_size;
    void *data = cthread->getMem({COYOTE_ALLOC_TYPE, (in_size)});
    std::memcpy(data, file_data + page->fileOffset + (jump_header ? page->header_size : 0), in_size);
    page->in_data = data;
    if (page->type == parquet_thrift::format::PageType::DATA_PAGE) {
        uint32_t out_size = page->encoding == parquet_thrift::format::Encoding::PLAIN
            ? page->uncompressed_page_size
            : page->num_values * page->byteWidth;
        void *out_data = cthread->getMem({COYOTE_ALLOC_TYPE, out_size});
        page->out_data = out_data;
    }
}


// Unmap output buffers from FPGA but keep memory allocated for Arrow table (not working)
void common::unmapOutputBuffers(const std::vector<row_group_info_compact>& row_groups, coyote::cThread* cthread) {
    DBG_1("Unmapping output buffers from FPGA...");
    int output_buffer_count = 0;
    
    // Only process the first row group (as per the current implementation)
    // if (!row_groups.empty()) {
    //     for (size_t col_idx = 0; col_idx < row_groups[0].columns.size(); col_idx++) {
    //         if (row_groups[0].columns[col_idx].output_buffer) {
    //             DBG_2("Unmapping output buffer " << row_groups[0].columns[col_idx].output_buffer << " for column " << col_idx);
    //             cthread->userUnmap(row_groups[0].columns[col_idx].output_buffer);  // Unmap from FPGA but keep memory
    //             // Note: Don't null the pointer here - Arrow needs it for buffer creation
    //             output_buffer_count++;
    //         }
    //     }
    // }
    
    DBG_2("Unmapped " << output_buffer_count << " output buffers from FPGA");
}

common::parquet_timing_result common::loadParquetFileFPGA(const std::string& file_path, 
                                                           std::shared_ptr<arrow::Table>& output_table, std::vector<int> excluded_columns, bool jump_header, int num_units, bool simulate_compression) {

    parquet_timing_result result(file_path, 0, 0, 0, 0);
    
    // FPGA config tracking system to prevent overwhelming the FPGA
    static constexpr int FPGA_CONFIG_BUFFER_SIZE = 50;  // Maximum number of configs ahead of completions
    static int sent_configs = 0;          // Total configs sent to FPGA

    std::ifstream file(file_path, std::ios::ate | std::ios::binary);
    if (!file) {
        std::cerr << "Cannot open file " << file_path << std::endl;
        return result;
    }


    // Create a conditional debug stream that only outputs if DBG_2 is active
#ifdef DEBUG_3
    std::ostream& debug_stream = DEBUG_OUT;
#else
    std::ostringstream null_stream;  // Discards all output
    std::ostream& debug_stream = null_stream;
#endif
    
    DBG_1("Starting analyseParquetFile");
    std::vector<struct common::row_group_info_compact> row_groups = common::analyseParquetFile(file_path, debug_stream);
    DBG_1("Finished analysing parquet file");
    DBG_2(common::toString(row_groups));
    assert(row_groups.size() == 1 && "Only one row group supported for now");

    // STEP 2: Process the parquet file
    DBG_1("Starting cThread");
    coyote::cThread cthread(0, getpid(), 0);
    DBG_2("cThread obtained");

    std::vector<int> column_to_core_mapping;
    if (!row_groups.empty()) {
        size_t num_columns = row_groups[0].columns.size();
        column_to_core_mapping.resize(num_columns);
        
        // Simple round-robin assignment of columns to threads
        for (size_t col_idx = 0; col_idx < num_columns; col_idx++) {
            column_to_core_mapping[col_idx] = col_idx % num_units;
        }
        
        DBG_2("Column to core mapping:");
        for (size_t col_idx = 0; col_idx < num_columns; col_idx++) {
            DBG_2("  Column " << col_idx << " -> Core " << column_to_core_mapping[col_idx]);
        }
    }

    // Initialize all threads
    for (int i = 0; i < num_units; i++) {
        common::hardResetUnit(&cthread, i);
        common::perfResetUnit(&cthread, i);
    }
    cthread.clearCompleted();


    // Performance timing variables
    auto overall_start = std::chrono::high_resolution_clock::now();
    auto memory_start = std::chrono::high_resolution_clock::now();
    auto memory_end = std::chrono::high_resolution_clock::now();
    auto setup_start = std::chrono::high_resolution_clock::now();
    auto completion_start = std::chrono::high_resolution_clock::now();
    auto completion_end = std::chrono::high_resolution_clock::now();

    int total_writes = 0;
    
    // Track actual transferred data sizes for performance metrics
    std::vector<size_t> total_input_transferred_core(num_units, 0);
    std::vector<size_t> total_header_transferred_core(num_units, 0);
    std::vector<size_t> total_output_transferred_core(num_units, 0);

    
    std::streampos file_size = file.tellg();
    file.seekg(0, std::ios::beg);
    char *file_data = (char *) malloc(file_size);
    file.read(file_data, file_size);

    memory_end = std::chrono::high_resolution_clock::now();

    void *in_data = cthread.getMem({COYOTE_ALLOC_TYPE, file_size});
    std::memcpy(in_data, file_data, file_size);

    
    DBG_1("File loaded: " << file_size << " bytes");
    result.file_size_bytes = file_size;


    // Pre-calculate total output buffer size per column and allocate buffers
    std::vector<size_t> column_output_offsets;
    column_output_offsets.resize(row_groups[0].columns.size(), 0);
    result.num_columns = row_groups[0].columns.size();
    result.num_rows = row_groups[0].num_rows;
    result.output_size_bytes = 0;
    
    for (size_t col_idx = 0; col_idx < row_groups[0].columns.size(); col_idx++) {
        size_t total_output_size = 0;
        // Calculate total output size for this column
        for (size_t i = 0; i < row_groups.size(); i++) {
            for (size_t j = 0; j < row_groups[i].columns[col_idx].pages.size(); j++) {
                const auto& page = row_groups[i].columns[col_idx].pages[j];
                if (page.type == parquet_thrift::format::PageType::DATA_PAGE) {
                    uint32_t out_size = common::calculateOutputSize(page);
                    total_output_size += out_size;
                }
            }
        }
        assert(total_output_size < std::numeric_limits<uint32_t>::max() && "Total output size exceeds uint32_t limit");
        // Allocate buffer for this column
        void* column_buffer = cthread.getMem({COYOTE_ALLOC_TYPE, static_cast<uint32_t>(total_output_size)});
        for (size_t i = 0; i < row_groups.size(); i++) {
            row_groups[i].columns[col_idx].output_buffer = column_buffer;
            row_groups[i].columns[col_idx].output_size = total_output_size;
        }        
        DBG_1("Column " << col_idx << ": " << total_output_size << " bytes output");
    }
    
    setup_start = std::chrono::high_resolution_clock::now();
    // Config writing and transfer invoke
    for (size_t i = 0; i < row_groups.size(); i++)
    {
        for (size_t col_idx = 0; col_idx < row_groups[i].columns.size(); col_idx++) {
            auto& column = row_groups[i].columns[col_idx];
            int core_idx = column_to_core_mapping[col_idx];

            for (size_t j = 0; j < column.pages.size(); j++)
            {
                struct common::page_info_compact& page = column.pages[j];
                
                // FPGA config flow control: Block if too many configs are ahead of completions
                int completed_reads = cthread.checkCompleted(coyote::CoyoteOper::LOCAL_READ);
                bool printed = false;
                auto sleep_start = std::chrono::high_resolution_clock::now();
                while ((sent_configs - completed_reads) >= FPGA_CONFIG_BUFFER_SIZE) {
                    if (!printed) {DBG_2("FPGA config buffer full (sent: " << sent_configs << ", completed: " << completed_reads 
                        << "), waiting for LOCAL_READ completions..."); printed = true;}
                    // Small delay to prevent busy waiting
                    std::this_thread::sleep_for(std::chrono::microseconds(1000));
                    // Check again for updated completion count from FPGA
                    int new_completed_reads = cthread.checkCompleted(coyote::CoyoteOper::LOCAL_READ);
                    if (new_completed_reads != completed_reads) printed = false;
                    completed_reads = new_completed_reads;
                    auto sleep_end = std::chrono::high_resolution_clock::now();
                    std::chrono::duration<double> sleep_time = sleep_end - sleep_start;
                    if (sleep_time.count() > 10) {
                        std::cerr << "Timeout, " << cthread.checkCompleted(coyote::CoyoteOper::LOCAL_READ) << " reads completed" << std::endl;
                        std::exit(1);
                    }
              }
                
                // Create a conditional debug stream for writeConfigToFPGA
#ifdef DEBUG_2
                std::ostream& config_debug_stream = DEBUG_OUT;
#else
                std::ostringstream null_config_stream;
                std::ostream& config_debug_stream = null_config_stream;
#endif
                int64_t config = common::generateConfig(&page, column.dictionary && j == (column.pages.size() - 1), jump_header, simulate_compression);
                common::writeConfigToFPGA(&cthread, config, core_idx);
                sent_configs++;
                DBG_3("FPGA config sent (total: " << sent_configs << ", completed reads: " << cthread.checkCompleted(coyote::CoyoteOper::LOCAL_READ) << ")");

                uint32_t in_size = jump_header ? page.compressed_page_size : page.compressed_page_size + page.header_size;
                // void *data = cthread.getMem({COYOTE_ALLOC_TYPE, in_size});
                // page.in_data = data;    // Store pointer in page structure for cleanup
                // page.out_data = nullptr; // Not used in this implementation

                size_t in_data_offset = page.fileOffset + (jump_header ? page.header_size : 0);
                page.in_data = static_cast<char*>(in_data) + in_data_offset;
                // Track input data size
                total_input_transferred_core[core_idx] += in_size;
                if (!jump_header) {
                    total_header_transferred_core[core_idx] += page.header_size;
                }
                
#ifdef DEBUG_3
                // Debug printing of input data for FPGA waveform viewer
                DBG_3("=== INPUT DATA DEBUG ===" << std::dec);
                DBG_3("Row Group: " << i << ", Column: " << col_idx << ", Page: " << j);
                DBG_3("Page Type: " << (page.type == parquet_thrift::format::PageType::DATA_PAGE ? "DATA_PAGE" : "DICT_PAGE"));
                DBG_3("Input Size: " << in_size << " bytes");
                DBG_3("Data (512 bits per line):");
                    // Print hex data with 512 bits (64 bytes) per line
                const uint8_t* byte_data = static_cast<const uint8_t*>(data);
                // Default to false (original byte order for Python testing)
                bool flip_bytes = false; 
                
                for (size_t byte_idx = 0; byte_idx < in_size; byte_idx += 64) {
                    // Print line number/offset
                    DEBUG_OUT << std::hex << std::setfill('0') << std::setw(8) << byte_idx << ": ";
                    
                    // Print 64 bytes (512 bits) per line with optional byte order flipping
                    for (size_t line_byte = 0; line_byte < 64; line_byte++) {
                        size_t byte_idx_to_use;
                        
                        if (flip_bytes) {
                            // Calculate reverse byte index within this line (63, 62, 61, ..., 0) for FPGA waveform viewer
                            byte_idx_to_use = byte_idx + (63 - line_byte);
                        } else {
                            // Use sequential byte index (0, 1, 2, ..., 63) for Python testing
                            byte_idx_to_use = byte_idx + line_byte;
                        }
                        
                        // Check if this byte exists in the data
                        if (byte_idx_to_use < in_size) {
                            DEBUG_OUT << std::hex << std::setfill('0') << std::setw(2) 
                                     << static_cast<int>(byte_data[byte_idx_to_use]) << " ";
                        } else {
                            DEBUG_OUT << "__ "; // Pad with underscores for missing bytes
                        }
                        
                        // Add space every 8 bytes for readability
                        if ((line_byte + 1) % 8 == 0) {
                            DEBUG_OUT << " ";
                        }
                    }
                    DEBUG_OUT << std::endl;
                }
#endif

                // Invoke input transfer with chunking
                int input_transfers = common::invokeWithChunking(&cthread, coyote::CoyoteOper::LOCAL_READ, page.in_data, in_size, true, core_idx);
                
                if (page.type == parquet_thrift::format::PageType::DATA_PAGE) {
                    uint32_t out_size = common::calculateOutputSize(page);
                    
                    // Use offset pointer into the pre-allocated column buffer
                    void *out_data = static_cast<char*>(column.output_buffer) + column_output_offsets[col_idx];
                    
                    // Invoke output transfer with chunking
                    int output_transfers = common::invokeWithChunking(&cthread, coyote::CoyoteOper::LOCAL_WRITE, out_data, out_size, true, core_idx);
                    total_writes += output_transfers;
                    
                    // Track output data size
                    total_output_transferred_core[core_idx] += out_size;
                    
                    // Update offset for next page in this column
                    column_output_offsets[col_idx] += out_size;
                }
            }
        }
    } 
    DBG_1("Processing " << total_writes << " writes...");
    
    completion_start = std::chrono::high_resolution_clock::now();
    while (cthread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) < total_writes) {
        auto end = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double> time = end - completion_start;
        if (time.count() > 10) {
            std::cerr << "Timeout, " << cthread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " of " << total_writes << std::endl;
            std::exit(1);
        }
    }
    completion_end = std::chrono::high_resolution_clock::now();
    auto overall_end = std::chrono::high_resolution_clock::now();

    // Read cycles
    std::vector<size_t> core_cycles_total(num_units, 0);
    std::vector<size_t> core_cycles_output_stalled(num_units, 0);
    std::vector<size_t> core_cycles_input_stalled(num_units, 0);
    for (int t = 0; t < num_units; t++) {
        core_cycles_total[t] = cthread.getCSR(static_cast<uint32_t>(common::CtrlRegs::TIMER_TOTAL_REG));
        core_cycles_output_stalled[t] = cthread.getCSR(static_cast<uint32_t>(common::CtrlRegs::TIMER_OUTPUT_STALLED_REG));
        core_cycles_input_stalled[t] = cthread.getCSR(static_cast<uint32_t>(common::CtrlRegs::TIMER_INPUT_STALLED_REG));
    }
    int total_cycles_total = 0;
    for (int t = 0; t < num_units; t++) {
        total_cycles_total = cthread.getCSR(static_cast<uint32_t>(common::CtrlRegs::TOTAL_TIMER_TOTAL_REG));
    }

    // Calculate timing durations with high precision (same as CPU reader)
    auto overall_time = std::chrono::duration_cast<std::chrono::duration<float, std::milli>>(overall_end - overall_start);
    auto processing_time = std::chrono::duration_cast<std::chrono::duration<float, std::milli>>(completion_end - setup_start);
    auto memory_time = std::chrono::duration_cast<std::chrono::duration<float, std::milli>>(memory_end - memory_start);
    auto coyote_memory_time = std::chrono::duration_cast<std::chrono::duration<float, std::milli>>(setup_start - memory_end);
    auto setup_time = std::chrono::duration_cast<std::chrono::duration<float, std::milli>>(completion_start - setup_start);
    auto completion_time = std::chrono::duration_cast<std::chrono::duration<float, std::milli>>(completion_end - completion_start);


    cthread.clearCompleted();

    // Cleanup: Free input buffers immediately after FPGA processing
    // DBG_1("Freeing input buffers...");
    // int input_buffer_count = 0;
    // for (size_t i = 0; i < row_groups.size(); i++) {
    //     for (size_t col_idx = 0; col_idx < row_groups[i].columns.size(); col_idx++) {
    //         auto& column = row_groups[i].columns[col_idx];
    //         for (size_t j = 0; j < column.pages.size(); j++) {
    //             if (column.pages[j].in_data) {
    //                 cthread.freeMem(column.pages[j].in_data);
    //                 column.pages[j].in_data = nullptr;  // Prevent double-free
    //                 input_buffer_count++;
    //             }
    //         }
    //     }
    // }
    // DBG_2("Freed " << input_buffer_count << " input buffers");
    
    // Unmap output buffers from FPGA but keep memory allocated for Arrow table
    // common::unmapOutputBuffers(row_groups, &cthread);
    
    // Free regular malloc'd memory (file data no longer needed)
    free(file_data);

    size_t total_input_transferred = 0;
    size_t total_output_transferred = 0;
    size_t total_header_transferred = 0;
    for (int t = 0; t < num_units; t++) {
        total_input_transferred += total_input_transferred_core[t];
        total_output_transferred += total_output_transferred_core[t];
        total_header_transferred += total_header_transferred_core[t];
    }


    result.total_time_milliseconds = overall_time.count();
    result.processing_time_milliseconds = processing_time.count();
    result.memory_transfer_time_milliseconds = memory_time.count();
    result.coyote_memory_transfer_time_milliseconds = coyote_memory_time.count();
    result.setup_time_milliseconds = setup_time.count();
    result.completion_time_milliseconds = completion_time.count();
    result.output_size_bytes = total_output_transferred;  // Set actual output size
    result.core_cycles_total = core_cycles_total;
    result.core_cycles_output_stalled = core_cycles_output_stalled;
    result.core_cycles_input_stalled = core_cycles_input_stalled;
    result.total_cycles_total = total_cycles_total;
    result.total_input_transferred = total_input_transferred_core;
    result.total_header_transferred = total_header_transferred_core;
    result.total_output_transferred = total_output_transferred_core;


    DBG_1(std::dec<< "Performance: " << total_cycles_total << " total");

    DBG_1("Timing Summary:");
    DBG_1("  Overall time: " << std::fixed << std::setprecision(2) << overall_time.count() << "ms");
    DBG_1("  Processing time: " << std::fixed << std::setprecision(2) << processing_time.count() << "ms");
    DBG_1("  Memory/file operations: " << std::fixed << std::setprecision(2) << memory_time.count() << "ms");
    DBG_1("  Coyote memory transfer time: " << std::fixed << std::setprecision(2) << coyote_memory_time.count() << "ms");
    DBG_1("  Setup time (non-blocking): " << std::fixed << std::setprecision(2) << setup_time.count() << "ms");
    DBG_1("  Completion wait time: " << std::fixed << std::setprecision(2) << completion_time.count() << "ms");
    
    
    DBG_1("Data Size Summary:");
    DBG_1("  Parquet file size: " << file_size << " bytes (" << std::fixed << std::setprecision(2) << (file_size / (1024.0 * 1024.0)) << " MB)");
    DBG_1("  Total input transferred: " << total_input_transferred << " bytes (" << std::fixed << std::setprecision(2) << (total_input_transferred / (1024.0 * 1024.0)) << " MB)");
    DBG_1("  Total output transferred: " << total_output_transferred << " bytes (" << std::fixed << std::setprecision(2) << (total_output_transferred / (1024.0 * 1024.0)) << " MB)");
    
    DBG_1("Throughput Metrics:");
    // max of cycles_total
    for (int t = 0; t < num_units; t++) {
        DBG_1("  Core " << t << ": " << core_cycles_total[t] << " total, " << core_cycles_output_stalled[t] << " output stalled cycles," << core_cycles_input_stalled[t] << " input stalled cycles");
        DBG_1("  Input throughput: " << std::fixed << std::setprecision(2) 
                << (total_input_transferred_core[t] / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
                << ", " << std::setprecision(2) << (static_cast<double>(total_input_transferred_core[t]) / core_cycles_total[t]) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_input_transferred_core[t]) / core_cycles_total[t]) / 4 << " GB/s");
        DBG_1("  Output throughput: " << std::fixed << std::setprecision(2) 
                << (total_output_transferred_core[t] / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
                << ", "  << std::setprecision(2) << (static_cast<double>(total_output_transferred_core[t]) / core_cycles_total[t]) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_output_transferred_core[t]) / core_cycles_total[t]) / 4 << " GB/s");
    }
    DBG_1("  Final: " << total_cycles_total << " total");
    DBG_1("  Input throughput: " << std::fixed << std::setprecision(2) 
            << (total_input_transferred / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
            << ", " << std::setprecision(2) << (static_cast<double>(total_input_transferred) / total_cycles_total) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_input_transferred) / total_cycles_total) / 4 << " GB/s");
    DBG_1("  Output throughput: " << std::fixed << std::setprecision(2) 
            << (total_output_transferred / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
            << ", "  << std::setprecision(2) << (static_cast<double>(total_output_transferred) / total_cycles_total) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_output_transferred) / total_cycles_total) / 4 << " GB/s");

    
    DBG_1("Performance Ratios:");
    DBG_1("  Compression ratio: " << std::fixed << std::setprecision(2) 
              << (static_cast<double>(total_output_transferred) / total_input_transferred) << "x");
    DBG_1("  File utilization: " << std::fixed << std::setprecision(1) 
              << (static_cast<double>(total_input_transferred) / file_size * 100.0) << "%");
    if (!jump_header) DBG_1("  Header transfer ratio: " << std::fixed << std::setprecision(2) 
              << (static_cast<double>(total_header_transferred) / total_input_transferred) * 100.0 << "%");


    // Construct Arrow table (will take ownership of output buffers)
    DBG_1("Constructing Arrow table with ownership transfer...");
    output_table = common::constructArrowTableFromBuffers(row_groups, &cthread);

    DBG_1("Finished reading parquet file");
    return result;
}


common::parquet_timing_result common::loadParquetFileCPU(const std::string& file_path, 
                                                           std::shared_ptr<arrow::Table>& output_table) {
    // Initialize timing result with filename
    std::filesystem::path path(file_path);
    std::string filename = path.filename().string();
    parquet_timing_result result(filename, 0, 0, 0, 0);
    
    try {
        // Get file size
        std::filesystem::path file_path_obj(file_path);
        if (!std::filesystem::exists(file_path_obj)) {
            std::cerr << "Error: File does not exist: " << file_path << std::endl;
            return result;
        }
        result.file_size_bytes = std::filesystem::file_size(file_path_obj);
        
        DBG_1("Starting CPU parquet reader for file: " << file_path << " (size: " << result.file_size_bytes << " bytes)");
        
        // Prepare Arrow table reader (similar to cpu_reader)
        std::unique_ptr<parquet::arrow::FileReader> reader = prepareArrowTableReader(file_path);
        DBG_1("Arrow table reader prepared successfully");
        
        // Log Arrow reader information
        const auto& build_info = arrow::GetBuildInfo();
        const auto& runtime_info = arrow::GetRuntimeInfo();
        int cpu_thread_count = arrow::GetCpuThreadPoolCapacity();
        
        DBG_1("Arrow Reader Information:");
        DBG_1("  Version: " << build_info.version_string);
        DBG_1("  Build Type: " << build_info.build_type);
        DBG_1("  CPU Thread Count: " << cpu_thread_count);
        DBG_1("  SIMD Level: " << runtime_info.simd_level);
        DBG_1("  Detected SIMD Level: " << runtime_info.detected_simd_level);
        DBG_1("  Compiler: " << build_info.compiler_id << " " << build_info.compiler_version);
        // Check threading configuration
        bool threading_enabled = reader->properties().use_threads();
        DBG_1("  Threading Enabled: " << (threading_enabled ? "Yes" : "No"));
        
        // Start total timing
        auto start_total = std::chrono::high_resolution_clock::now();
        
        // This reads the entire table contained in the file.
        // Afterwards, all data is present and obtainable as raw arrays.
        DBG_1("Reading parquet table data...");
        auto read_result = reader->ReadTable(&output_table);
        if (!read_result.ok()) {
            DBG_ERROR("Failed to read Parquet table from file " << file_path);
            DBG_ERROR("Arrow error: " << read_result.ToString());
            std::cerr << "Error reading Parquet table from file " << file_path << std::endl;
            std::cerr << "Arrow error details: " << read_result.ToString() << std::endl;
            return result;
        }
        DBG_1("Successfully read parquet table");
        
        // Stop total timing
        auto end_total = std::chrono::high_resolution_clock::now();
        // Convert to milliseconds with high precision
        auto total_time_ms = std::chrono::duration_cast<std::chrono::duration<float, std::milli>>(end_total - start_total);
        result.total_time_milliseconds = total_time_ms.count();
        
        // Calculate output table size in memory
        if (output_table) {
            result.num_rows = output_table->num_rows();
            result.num_columns = output_table->num_columns();
            
            DBG_2("Table successfully loaded: " << result.num_rows << " rows, " << result.num_columns << " columns");
            
            // Calculate approximate memory usage of the arrow table
            size_t memory_usage = 0;
            for (int i = 0; i < output_table->num_columns(); ++i) {
                auto column = output_table->column(i);
                for (int j = 0; j < column->num_chunks(); ++j) {
                    auto array = column->chunk(j);
                    // Sum up the size of all buffers in the array
                    for (const auto& buffer : array->data()->buffers) {
                        if (buffer) {
                            memory_usage += buffer->size();
                        }
                    }
                }
            }
            result.output_size_bytes = memory_usage;
        }
        
        // Memory transfer time is not available in this basic implementation
        // It would need to be measured separately if transferring data to/from FPGA or GPU
        result.memory_transfer_time_milliseconds = 0.0f;
        
        // Validate the table (similar to cpu_reader assertions)
        if (output_table->num_columns() == 0) {
            std::cerr << "Warning: Table has no columns" << std::endl;
        }
        
        // Check that threading is disabled (for consistency with cpu_reader)
        if (reader.get()->properties().use_threads()) {
            std::cerr << "Warning: Threading is enabled in reader properties" << std::endl;
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Exception in loadParquetWithTiming: " << e.what() << std::endl;
        // Return partial result with error information
        return result;
    }
    
    return result;
}

// Helper function to calculate correct output size for data pages
uint32_t common::calculateOutputSize(const common::page_info_compact& page) {
    if (page.type != parquet_thrift::format::PageType::DATA_PAGE) {
        return 0;
    }
    
    if (page.encoding == parquet_thrift::format::Encoding::PLAIN) {
        // Plain pages use uncompressed page size
        return page.uncompressed_page_size;
    } else {
        // For non-plain boolean encodings, use bit-packed size: (num_values + 7) / 8
        // For non-plain non-boolean encodings, use num_values * byteWidth
        if (page.byteWidth == 1) {
            return (page.num_values + 7) / 8;
        } else {
            return page.num_values * page.byteWidth;
        }
    }
}

// Helper function to invoke transfers with chunking for streams larger than 128MB (won't be neccessary in Parquet)
uint32_t common::invokeWithChunking(coyote::cThread* cthread, coyote::CoyoteOper oper, 
                                   void* data, uint32_t size, bool is_last, uint32_t destId) {
    const uint32_t MAX_CHUNK_SIZE = 128 * 1024 * 1024; // 128MB
    
    if (size <= MAX_CHUNK_SIZE) {
        // Single transfer
        coyote::localSg sg = {data, size, coyote::STRM_HOST, destId};
        cthread->invoke(oper, sg, is_last);
        return 1u; // Number of transfers
    } else {
        // Multiple transfers
        uint32_t remaining_size = size;
        uint32_t offset = 0;
        uint32_t transfer_count = 0;
        
        while (remaining_size > 0) {
            uint32_t chunk_size = std::min(remaining_size, MAX_CHUNK_SIZE);
            void* chunk_data = static_cast<char*>(data) + offset;
            
            coyote::localSg sg = {chunk_data, chunk_size, coyote::STRM_HOST, destId};
            bool is_last_chunk = (remaining_size <= MAX_CHUNK_SIZE) && is_last;
            cthread->invoke(oper, sg, is_last_chunk);
            
            remaining_size -= chunk_size;
            offset += chunk_size;
            transfer_count++;
        }
        return transfer_count;
    }
}

// Helper function to convert Parquet physical types to Arrow types
std::shared_ptr<arrow::DataType> common::parquetTypeToArrowType(int32_t physical_type) {
    switch (static_cast<parquet::Type::type>(physical_type)) {
        case parquet::Type::BOOLEAN:
            return arrow::boolean();
        case parquet::Type::INT32:
            return arrow::int32();
        case parquet::Type::INT64:
            return arrow::int64();
        case parquet::Type::FLOAT:
            return arrow::float32();
        case parquet::Type::DOUBLE:
            return arrow::float64();
        default:
            throw std::runtime_error("Unsupported Parquet type: " + std::to_string(physical_type));
    }
}

// Function to construct Arrow table from column output buffers
std::shared_ptr<arrow::Table> common::constructArrowTableFromBuffers(
    const std::vector<row_group_info_compact>& row_groups, coyote::cThread* cthread) {
    
    if (row_groups.empty()) {
        throw std::runtime_error("No row groups provided");
    }
    
    // Assume all row groups have the same column structure
    const auto& first_row_group = row_groups[0];
    size_t num_columns = first_row_group.columns.size();
    
    if (num_columns == 0) {
        throw std::runtime_error("No columns found in row groups");
    }
    
    // Calculate total number of rows across all row groups
    int64_t total_rows = 0;
    for (const auto& row_group : row_groups) {
        total_rows += row_group.num_rows;
    }
    
    std::vector<std::shared_ptr<arrow::Field>> fields;
    std::vector<std::shared_ptr<arrow::Array>> arrays;
    
    // Process each column
    for (size_t col_idx = 0; col_idx < num_columns; col_idx++) {
        const auto& first_column = first_row_group.columns[col_idx];
        
        // Use the pre-converted Arrow type from analyseParquetFile
        std::shared_ptr<arrow::DataType> arrow_type = first_column.arrow_type;
        if (!arrow_type) {
            throw std::runtime_error("Invalid Arrow type for column " + std::to_string(col_idx));
        }
        
        // Create field name from path_in_schema
        std::string field_name = first_column.path_in_schema.empty() 
            ? "column_" + std::to_string(col_idx)
            : first_column.path_in_schema[0];  // Use first element of path
        
        // Create field
        auto field = arrow::field(field_name, arrow_type);
        fields.push_back(field);
        
        // Calculate total values for this column across all row groups
        int64_t total_values = 0;
        size_t total_buffer_size = 0;
        
        for (const auto& row_group : row_groups) {
            if (col_idx < row_group.columns.size()) {
                const auto& column = row_group.columns[col_idx];
                total_values += column.num_values;
                total_buffer_size += column.output_size;
            }
        }
        
        if (total_values == 0) {
            // Create empty array using ArrayData directly (like the pattern in maximus code)
            auto array_data = arrow::ArrayData::Make(arrow_type, 0, {nullptr, nullptr}, 0);
            auto empty_array = arrow::MakeArray(array_data);
            arrays.push_back(empty_array);
            continue;
        }
        
        // For simplicity, assume all data for a column is contiguous in the first row group's buffer
        // In practice, you might need to concatenate buffers from multiple row groups
        const auto& column = first_row_group.columns[col_idx];
        
        if (!column.output_buffer || column.output_size == 0) {
            throw std::runtime_error("Invalid output buffer for column " + std::to_string(col_idx));
        }
        
        // Create Arrow buffer with custom deleter that properly cleans up coyote memory
        // This approach uses Arrow's shared_ptr custom deleter instead of inheritance
        auto buffer = std::shared_ptr<arrow::Buffer>(
            new arrow::Buffer(
                static_cast<const uint8_t*>(column.output_buffer), 
                static_cast<int64_t>(column.output_size)
            )
            // Custom deleter: when Arrow is done, free Coyote allocation then delete Buffer wrapper
            // [column_ptr = column.output_buffer, cthread](arrow::Buffer* b) {
            //     DBG_2("Arrow buffer deleter freeing coyote memory " << column_ptr);
            //     cthread->freeMem(column_ptr);
            //     delete b;
            // }
        );
        
        // Create ArrayData
        std::shared_ptr<arrow::ArrayData> array_data;
        
        if (arrow_type->id() == arrow::Type::BOOL) {
            // For boolean arrays, we need to handle bit-packing
            array_data = arrow::ArrayData::Make(
                arrow_type,
                total_values,
                {nullptr, buffer},  // No null bitmap, values buffer
                0  // null count
            );
        } else {
            // For fixed-width types
            array_data = arrow::ArrayData::Make(
                arrow_type,
                total_values,
                {nullptr, buffer},  // No null bitmap, values buffer
                0  // null count
            );
        }
        
        // Create Array from ArrayData
        auto array = arrow::MakeArray(array_data);
        arrays.push_back(array);
    }
    
    // Create schema
    auto schema = arrow::schema(fields);
    
    // Create table
    auto table = arrow::Table::Make(schema, arrays);
    
    return table;
}
