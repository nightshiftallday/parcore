#pragma once

#include <iostream>
#include <filesystem>
#include <fstream>
#include <string>
#include <cstring>
#include <vector>
#include <unordered_map>

#include <iomanip>
#include <cstdint>
#include <algorithm>
#include <any>


#include <chrono>
#include "parquet_types.h"

#include <parquet/arrow/reader.h>
#include <arrow/io/api.h>
#include <arrow/table.h>
#include <arrow/type.h>
#include <arrow/array.h>
#include <arrow/type_fwd.h>
#include <arrow/buffer.h>
#include <thrift/protocol/TCompactProtocol.h>
#include <thrift/transport/TBufferTransports.h>

#include <cThread.hpp>


/*
 * Debug System Usage:
 * ===================
 * To enable debug output, compile with:
 *   cmake -DDEBUG=ON -DDEBUG_1=ON -DDEBUG_2=ON -DDEBUG_3=ON ..
 * 
 * Debug Levels:
 *   DEBUG     - Enables main debug stream (required for all others)
 *   DEBUG_1   - Basic operations and flow control (DBG_1)
 *   DEBUG_2   - Configuration and metadata operations (DBG_2)  
 *   DEBUG_3   - Detailed data dumps and verbose operations (DBG_3)
 * 
 * Available Macros:
 *   DBG_1(msg)    - Level 1 debug output
 *   DBG_2(msg)    - Level 2 debug output  
 *   DBG_3(msg)    - Level 3 debug output
 *   DBG_INFO(msg) - General info (when DEBUG is set)
 *   DBG_WARN(msg) - Warning messages (when DEBUG is set)
 *   DBG_ERROR(msg)- Error messages (when DEBUG is set)
 *   DEBUG_OUT    - Direct access to debug stream
 */
// Simple macro to choose allocation type based on CMake option
#ifdef USE_HUGEPAGES
    #define COYOTE_ALLOC_TYPE coyote::CoyoteAllocType::HPF
#else
    #define COYOTE_ALLOC_TYPE coyote::CoyoteAllocType::REG
#endif

// Convenience macro for getMem calls
#define GET_MEM(cthread, size) cthread.getMem({COYOTE_ALLOC_TYPE, (size)})


// Main debug output stream - only active when DEBUG is defined
#ifdef DEBUG
#define DEBUG_OUT std::cout
#else
#define DEBUG_OUT 0 && std::cout
#endif

// Debug level 1: Basic operations and flow control
#ifdef DEBUG_1
#define DBG_1(msg) do { \
    if (DEBUG_OUT) { \
        DEBUG_OUT << "[DBG_1] " << msg << std::endl; \
    } \
} while ( false )
#else
#define DBG_1(msg) do { } while ( false )
#endif

// Debug level 2: Configuration and metadata operations  
#ifdef DEBUG_2
#define DBG_2(msg) do { \
    if (DEBUG_OUT) { \
        DEBUG_OUT << "[DBG_2] " << msg << std::endl; \
    } \
} while ( false )
#else
#define DBG_2(msg) do { } while ( false )
#endif

// Debug level 3: Detailed data dumps and verbose operations
#ifdef DEBUG_3
#define DBG_3(msg) do { \
    if (DEBUG_OUT) { \
        DEBUG_OUT << "[DBG_3] " << msg << std::endl; \
    } \
} while ( false )
#else
#define DBG_3(msg) do { } while ( false )
#endif

// Convenience macro for debug output that's always available when DEBUG is set
#ifdef DEBUG
#define DBG_INFO(msg) do { DEBUG_OUT << "[INFO] " << msg << std::endl; } while ( false )
#define DBG_WARN(msg) do { DEBUG_OUT << "[WARN] " << msg << std::endl; } while ( false )
#define DBG_ERROR(msg) do { DEBUG_OUT << "[ERROR] " << msg << std::endl; } while ( false )
#else
#define DBG_INFO(msg) do { } while ( false )
#define DBG_WARN(msg) do { } while ( false )
#define DBG_ERROR(msg) do { } while ( false )
#endif


namespace common {

std::string getPrintString(uint64_t val, std::unordered_map<uint64_t, std::string> map);
void printBuffer(const void* buffer, size_t size,
    size_t byte_width = 1,
    size_t values_per_line = 8,
    bool hex_output = true,
    size_t max_values = SIZE_MAX,
    const std::string& mode = "binary",
    const std::string& endian = "little",
    std::ostream& out = std::cout,
    int32_t physical_type = 0,
    bool use_formatting = true);

std::unique_ptr<parquet::arrow::FileReader> prepareArrowTableReader(std::string filePath);



struct page_info_compact{
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
    void *in_data;
    void *out_data;
};


struct column_chunk_info_compact {
    std::vector<struct page_info_compact> pages;
    bool dictionary;
    std::vector<std::string>  path_in_schema;
    
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
    
    /**
     * total byte size of all uncompressed pages in this column chunk (including the headers) *
     */
    int64_t total_uncompressed_size;
    /**
     * total byte size of all compressed, and potentially encrypted, pages
     * in this column chunk (including the headers) *
     */
    int64_t total_compressed_size;
    
    // Fields for Arrow table construction
    void* output_buffer;                // Pointer to the raw output buffer data
    size_t output_size;          // Size of the output buffer in bytes
    std::shared_ptr<arrow::DataType> arrow_type;  // Converted Arrow data type
};

struct row_group_info_compact {
    std::vector<struct column_chunk_info_compact> columns;
    
    // Row group metadata
    int64_t num_rows;           // Number of rows in this row group
    int64_t total_byte_size;    // Total uncompressed byte size
    int64_t total_compressed_size; // Total compressed byte size
    int32_t ordinal;            // Row group ordinal
};


enum class CtrlRegs : uint32_t {
    HARD_RESET_REG = 0,
    PERF_RESET_REG = 1,
    CONFIG_WRITE_REG = 2,
    OVERFLOW_CLR_REG = 3,
    TIMER_TOTAL_REG = 4,
    TIMER_OUTPUT_STALLED_REG = 5,
    TIMER_INPUT_STALLED_REG = 6,
    OUT_CHUNK_CNT_REG = 7,
    PAGES_DONE_CNT_REG = 8,
    
    TOTAL_TIMER_TOTAL_REG = 9
    };



const uint32_t NUM_CTRL_REGS = 16; // Must be base 2

// Function to calculate register address for multi-unit designs
// For single unit (default), unit_id=0, so address = register_index
// For multiple units, address = (unit_id * 8) + register_index
inline uint64_t get_unit_register_address(CtrlRegs register_index, int unit_id = 0) {
    return (unit_id * NUM_CTRL_REGS) + static_cast<uint32_t>(register_index);
}

// Helper function to issue hard reset for a specific unit
// This will assert reset for HARD_RESET_CYCLES clock cycles, then auto-release
inline void hardResetUnit(coyote::cThread* cthread, int unit_id = 0) {
    uint32_t hard_reset_addr = get_unit_register_address(CtrlRegs::HARD_RESET_REG, unit_id);
    cthread->setCSR(1, hard_reset_addr);  // Any value triggers reset
}

// Helper function to issue performance counter reset for a specific unit  
inline void perfResetUnit(coyote::cThread* cthread, int unit_id = 0) {
    uint32_t perf_reset_addr = get_unit_register_address(CtrlRegs::PERF_RESET_REG, unit_id);
    cthread->setCSR(1, perf_reset_addr);  // Any value triggers reset
}
inline void writeConfigToFPGA(coyote::cThread* cthread, int64_t config, int unit_id = 0) {
    uint32_t oofset = get_unit_register_address(CtrlRegs::CONFIG_WRITE_REG, unit_id);
    cthread->setCSR(config, oofset); 
}


const std::unordered_map<uint64_t, std::string> compressionToString = {
    { parquet_thrift::format::CompressionCodec::UNCOMPRESSED, "Uncompressed" },
    { parquet_thrift::format::CompressionCodec::SNAPPY, "Snappy" }
};
const std::unordered_map<uint64_t, std::string> encodingToString = {
    { parquet_thrift::format::Encoding::PLAIN, "Plain" },
    { parquet_thrift::format::Encoding::PLAIN_DICTIONARY, "Plain Dictionary" },
    { parquet_thrift::format::Encoding::RLE, "RLE" },
    { parquet_thrift::format::Encoding::BIT_PACKED, "Bit Packed" },
    { parquet_thrift::format::Encoding::DELTA_BINARY_PACKED, "Delta Binary" },
    { parquet_thrift::format::Encoding::DELTA_LENGTH_BYTE_ARRAY, "Delta Length Byte" },
    { parquet_thrift::format::Encoding::DELTA_BYTE_ARRAY, "Delta Byte Array" },
    { parquet_thrift::format::Encoding::RLE_DICTIONARY, "RLE Dictionary" },
    { parquet_thrift::format::Encoding::BYTE_STREAM_SPLIT, "Byte Stream Split" }
};
std::vector<struct row_group_info_compact> analyseParquetFile(std::string filename, std::ostream& debug_out = DEBUG_OUT);
// Analyse parquet file and write detailed analysis to text file and binary file
// Byte widths are inferred per column from physical types
// Only supports: BOOLEAN, INT32, INT64, FLOAT, DOUBLE
// Aborts with error if unsupported types are found
void analyseParquetFileToFile(std::string filepath);
int64_t generateConfig(page_info_compact* page, bool setResetBit, bool jump_header=true, bool simulate_compression=false);
void readyMemoryBuffers(coyote::cThread* cthread, page_info_compact* page, char *file_data, size_t file_size, bool jump_header);
void unmapOutputBuffers(const std::vector<row_group_info_compact>& row_groups, coyote::cThread* cthread);

void printBufferHex(const void* buffer, size_t size, size_t bytesPerValue);


// Timing result structure for benchmarking parquet file loading
struct parquet_timing_result {
    std::string filename;           // Filename as index
    float total_time_milliseconds;  // Total time to load the parquet file in milliseconds
    size_t file_size_bytes;         // Size of the input parquet file in bytes
    size_t output_size_bytes;       // Size of the output arrow table in bytes (memory usage)
    float memory_transfer_time_milliseconds; // Memory transfer time if available, 0.0f if not measured
    float coyote_memory_transfer_time_milliseconds; // Coyote memory transfer time if available, 0.0f if not measured
    float setup_time_milliseconds; // Setup time if available, 0.0f if not measured
    float completion_time_milliseconds; // Completion time if available, 0.0f if not measured
    float processing_time_milliseconds; // Processing time if available, 0.0f if not measured

    size_t num_rows;                // Number of rows in the table
    size_t num_columns;             // Number of columns in the table
    std::vector<size_t> total_input_transferred; // Total input transferred in bytes
    std::vector<size_t> total_header_transferred; // Total header transferred in bytes
    std::vector<size_t> total_output_transferred; // Total output transferred in bytes
    std::vector<size_t> core_cycles_total;            // Total cycles
    std::vector<size_t> core_cycles_output_stalled;          // Total stalled cycles
    std::vector<size_t> core_cycles_input_stalled;          // Total stalled cycles
    
    size_t total_cycles_total;            // Total cycles
    // Constructor
    parquet_timing_result() : filename(""), total_time_milliseconds(0.0f), file_size_bytes(0), 
                             output_size_bytes(0), memory_transfer_time_milliseconds(0.0f), 
                             setup_time_milliseconds(0.0f), completion_time_milliseconds(0.0f),
                             processing_time_milliseconds(0.0f),
                             num_rows(0), num_columns(0), total_input_transferred(0),
                             total_header_transferred(0), total_output_transferred(0),
                             core_cycles_total(0), core_cycles_output_stalled(0), core_cycles_input_stalled(0),
                             total_cycles_total(0) {}
    
    // Constructor with parameters
    parquet_timing_result(const std::string& fname, size_t file_size, 
                         size_t output_size, size_t rows, size_t cols)
        : filename(fname), file_size_bytes(file_size),
          output_size_bytes(output_size),
          num_rows(rows), num_columns(cols) {}
};

// Function to load parquet file and measure timing for benchmarking
parquet_timing_result loadParquetFileCPU(const std::string& file_path, 
    std::shared_ptr<arrow::Table>& output_table);
parquet_timing_result loadParquetFileFPGA(const std::string& file_path, 
std::shared_ptr<arrow::Table>& output_table, std::vector<int> excluded_columns, bool jump_header=true, int num_units=1, bool simulate_compression=false);

// Helper functions for FPGA processing
uint32_t calculateOutputSize(const page_info_compact& page);
uint32_t invokeWithChunking(coyote::cThread* cthread, coyote::CoyoteOper oper, 
void* data, uint32_t size, bool is_last, uint32_t destId = 0);

// Arrow table construction
std::shared_ptr<arrow::DataType> parquetTypeToArrowType(int32_t physical_type);
std::shared_ptr<arrow::Table> constructArrowTableFromBuffers(
const std::vector<row_group_info_compact>& row_groups, coyote::cThread* cthread);





// PRINTING FUNCTIONS

inline parquet_thrift::format::CompressionCodec::type ToParquetCompressionCodec(arrow::Compression::type arrow_codec) {
    using arrow::Compression;
    using parquet_thrift::format::CompressionCodec;

    switch (arrow_codec) {
        case Compression::UNCOMPRESSED:
            return CompressionCodec::UNCOMPRESSED;
        case Compression::SNAPPY:
            return CompressionCodec::SNAPPY;
        case Compression::GZIP:
            return CompressionCodec::GZIP;
        case Compression::BROTLI:
            return CompressionCodec::BROTLI;
        case Compression::LZ4_FRAME:
            return CompressionCodec::LZ4;
        case Compression::ZSTD:
            return CompressionCodec::ZSTD;
        default:
            throw std::invalid_argument("Unsupported Arrow compression codec");
    }
}



// Compact variant toString functions
inline std::string toString(const page_info_compact& page, int indent_level = 0) {
    std::ostringstream oss;
    std::string indent(indent_level * 2, ' ');
    oss << indent << "PageInfoCompact: {"
        << "Type: " << page.type << ", "
        << "UncompressedSize: " << page.uncompressed_page_size << ", "
        << "CompressedSize: " << page.compressed_page_size << ", "
        << "NumValues: " << page.num_values << ", "
        << "HeaderSize: " << page.header_size << ", "
        << "Encoding: " << page.encoding << ", "
        << "Compression: " << page.compression << ", "
        << "isDefSet: " << std::boolalpha << page.isDefSet << ", "
        << "isRefSet: " << std::boolalpha << page.isRefSet << ", "
        << "ByteWidth: " << page.byteWidth << ", "
        << "FileOffset: " << page.fileOffset << "}";
    return oss.str();
}

inline std::string toString(const column_chunk_info_compact& column, int indent_level = 0) {
    std::ostringstream oss;
    std::string indent(indent_level * 2, ' ');
    oss << indent << "ColumnChunkInfoCompact { "
        << "dictionary: " << std::boolalpha << column.dictionary << ", "
        << "num_values: " << column.num_values << ", "
        << "total_uncompressed_size: " << column.total_uncompressed_size << ", "
        << "total_compressed_size: " << column.total_compressed_size << ", "
        << "output_buffer: " << column.output_buffer << ", "
        << "output_size: " << column.output_size << "\n";
    oss << indent << "  path_in_schema: [";
    for (size_t i = 0; i < column.path_in_schema.size(); ++i) {
        if (i > 0) oss << ", ";
        oss << "\"" << column.path_in_schema[i] << "\"";
    }
    oss << "]\n";
    oss << indent << "  pages: [\n";
    for (const auto& page : column.pages) {
        oss << toString(page, indent_level + 2) << ",\n";
    }
    oss << indent << "]}";
    return oss.str();
}

inline std::string toString(const row_group_info_compact& group, int indent_level = 0) {
    std::ostringstream oss;
    std::string indent(indent_level * 2, ' ');
    oss << "{ columns: [\n";
    for (const auto& column : group.columns) {
        oss << toString(column, indent_level + 1) << ",\n";
    }
    oss << indent << "]}";
    return oss.str();
}

inline std::string toString(const std::vector<row_group_info_compact>& groups) {
    std::ostringstream oss;
    oss << "RowGroupsCompact [\n";
    for (size_t i = 0; i < groups.size(); ++i) {
        oss << "  (" << i << ") " << toString(groups[i], 1) << "\n";
    }
    oss << "]";
    return oss.str();
}
}