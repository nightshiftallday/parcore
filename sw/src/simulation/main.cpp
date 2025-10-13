/**
    * Copyright (c) 2021, Systems Group, ETH Zurich
    * All rights reserved.
    *
    * Redistribution and use in source and binary forms, with or without modification,
    * are permitted provided that the following conditions are met:
    *
    * 1. Redistributions of source code must retain the above copyright notice,
    * this list of conditions and the following disclaimer.
    * 2. Redistributions in binary form must reproduce the above copyright notice,
    * this list of conditions and the following disclaimer in the documentation
    * and/or other materials provided with the distribution.
    * 3. Neither the name of the copyright holder nor the names of its contributors
    * may be used to endorse or promote products derived from this software
    * without specific prior written permission.
    *
    * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
    * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
    * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
    * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
    * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    */

#include <common.h>
#include <memory>

// Enum for buffer printing modes
enum class PrintMode {
    NONE,
    VALUES,
    HEX
};

// Enum for formatting options
enum class FormattingMode {
    COMPACT,
    FORMATTED
};

int main(int argc, char *argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <parquet-file> [--sendHeaders] [--skipBool] [--print-values] [--print-hex] [--format-compact] [--format-formatted] [--flip-bytes] [--num-threads <N>] [--simulate-compression]" << std::endl;
        std::cerr << "  --sendHeaders: Include headers in processing" << std::endl;
        std::cerr << "  --print-hex: Print buffer contents as hexadecimal" << std::endl;
        std::cerr << "  --format-compact: Compact output formatting (default)" << std::endl;
        std::cerr << "  --format-formatted: Formatted output with padding" << std::endl;
        std::cerr << "  --flip-bytes: Flip byte order for FPGA waveform viewer (default: original order for Python testing)" << std::endl;
        std::cerr << "  --num-threads <N>: Number of cThreads to create (default: 1)" << std::endl;
        std::cerr << "  --simulate-compression: Simulate compression" << std::endl;
        return 1;
    }

    const std::string file_name = argv[1];
    bool jump_header = true; // Default to true (jump header)
    bool skip_bool = false; // Default to false (process all columns)
    PrintMode print_mode = PrintMode::NONE; // Default to no printing
    FormattingMode format_mode = FormattingMode::COMPACT; // Default to compact formatting
    bool flip_bytes = false; // Default to false (original byte order for Python testing)
    int num_threads = 1; // Default to 1 thread
    int num_units = 1; // Default to 1 unit
    bool simulate_compression = false; // Default to false (don't simulate compression)


    // Check for optional flags
    for (int i = 2; i < argc; i++) {
        if (std::string(argv[i]) == "--sendHeaders") {
            jump_header = false; // Don't jump header when flag is present
        } else if (std::string(argv[i]) == "--skipBool") {
            skip_bool = true; // Skip boolean columns
        } else if (std::string(argv[i]) == "--print-values") {
            print_mode = PrintMode::VALUES;
        } else if (std::string(argv[i]) == "--print-hex") {
            print_mode = PrintMode::HEX;
        } else if (std::string(argv[i]) == "--format-compact") {
            format_mode = FormattingMode::COMPACT;
        } else if (std::string(argv[i]) == "--format-formatted") {
            format_mode = FormattingMode::FORMATTED;
        } else if (std::string(argv[i]) == "--flip-bytes") {
            flip_bytes = true; // Flip byte order for FPGA waveform viewer
        } else if (std::string(argv[i]) == "--num-units") {
            if (i + 1 < argc) {
                num_units = std::atoi(argv[i + 1]);
                if (num_units <= 0) {
                    std::cerr << "Error: num-units must be a positive integer" << std::endl;
                    return 1;
                }
                i++; // Skip the next argument since it's the number
            } else {
                std::cerr << "Error: --num-units requires a number argument" << std::endl;
                return 1;
            }
        } else if (std::string(argv[i]) == "--simulate-compression") {
            simulate_compression = true; // Simulate compression when flag is present
        }
    }

    if (jump_header) {
        DEBUG_OUT << "Processing without headers" << std::endl;
    } else {
        DEBUG_OUT << "Processing with headers" << std::endl;
    }
    
    if (skip_bool) {
        DEBUG_OUT << "Skipping boolean columns" << std::endl;
    }
    
    // Print mode debug output
    switch (print_mode) {
        case PrintMode::NONE:
            DEBUG_OUT << "Buffer printing: disabled" << std::endl;
            break;
        case PrintMode::VALUES:
            DEBUG_OUT << "Buffer printing: values" << std::endl;
            break;
        case PrintMode::HEX:
            DEBUG_OUT << "Buffer printing: hex" << std::endl;
            break;
    }
    
    // Format mode debug output
    if (print_mode != PrintMode::NONE) {
        switch (format_mode) {
            case FormattingMode::COMPACT:
                DEBUG_OUT << "Output formatting: compact" << std::endl;
                break;
            case FormattingMode::FORMATTED:
                DEBUG_OUT << "Output formatting: formatted" << std::endl;
                break;
        }
    }
    
    // Byte order debug output
    if (print_mode != PrintMode::NONE) {
        if (flip_bytes) {
            DEBUG_OUT << "Byte order: flipped (for FPGA waveform viewer)" << std::endl;
        } else {
            DEBUG_OUT << "Byte order: original (for Python testing)" << std::endl;
        }
    }
    
    DEBUG_OUT << "Number of threads: " << num_threads << std::endl;

    //
    std::ifstream file(file_name, std::ios::ate | std::ios::binary);
    if (!file) {
        std::cerr << "Cannot open file " << file_name << std::endl;
        return 1;
    }
    DEBUG_OUT << "Starting cThread" << std::endl;
    coyote::cThread cthread(0, getpid(), 0);
    DEBUG_OUT << "cThread obtained" << std::endl;
    

    for (int reps = 0; reps < 2; reps++) {

        auto row_groups = common::analyseParquetFile(file_name);
        DEBUG_OUT << common::toString(row_groups) << std::endl;
        // Create mapping from column index to cThread array index
    std::vector<int> column_to_core_mapping;
    if (!row_groups.empty()) {
        size_t num_columns = row_groups[0].columns.size();
        column_to_core_mapping.resize(num_columns);
        
        // Simple round-robin assignment of columns to threads
        for (size_t col_idx = 0; col_idx < num_columns; col_idx++) {
            column_to_core_mapping[col_idx] = col_idx % num_units;
        }
        
        DEBUG_OUT << "Column to core mapping:" << std::endl;
        for (size_t col_idx = 0; col_idx < num_columns; col_idx++) {
            DEBUG_OUT << "  Column " << col_idx << " -> Core " << column_to_core_mapping[col_idx] << std::endl;
        }
    }


    // Performance timing variables
    auto overall_start = std::chrono::high_resolution_clock::now();
    auto memory_start = std::chrono::high_resolution_clock::now();
    auto memory_end = std::chrono::high_resolution_clock::now();
    auto setup_start = std::chrono::high_resolution_clock::now();
    auto completion_start = std::chrono::high_resolution_clock::now();
    auto completion_end = std::chrono::high_resolution_clock::now();



    // Filter out boolean columns if requested
    if (skip_bool) {
        for (auto& row_group : row_groups) {
            // Remove boolean columns (byteWidth == 1)
            row_group.columns.erase(
                std::remove_if(row_group.columns.begin(), row_group.columns.end(),
                    [](const auto& col) { return col.byteWidth == 1; }),
                row_group.columns.end()
            );
        }
        DEBUG_OUT << "Filtered out boolean columns" << std::endl;
    }


    // Initialize all threads
    for (int i = 0; i < num_units; i++) {
        common::hardResetUnit(&cthread, i);
        common::perfResetUnit(&cthread, i);
    }
    cthread.clearCompleted();
    

    int total_writes = 0;
    
    // Track actual transferred data sizes for performance metrics
    std::vector<size_t> total_input_transferred_core(num_units, 0);
    std::vector<size_t> total_output_transferred_core(num_units, 0);
    

    
    memory_start = std::chrono::high_resolution_clock::now();
    
    std::streampos file_size = file.tellg();
    file.seekg(0, std::ios::beg);
    char *file_data = (char *) malloc(file_size);
    file.read(file_data, file_size);
    
    memory_end = std::chrono::high_resolution_clock::now();

    void *in_data = cthread.getMem({COYOTE_ALLOC_TYPE, file_size});
    std::memcpy(in_data, file_data, file_size);

    DEBUG_OUT << "File loaded: " << file_size << " bytes" << std::endl;

    // Pre-calculate total output buffer size per column and allocate buffers
    std::vector<void*> column_output_buffers;
    std::vector<size_t> column_output_offsets;
    
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
        
        // Allocate buffer for this column
        void* column_buffer = cthread.getMem({COYOTE_ALLOC_TYPE, total_output_size});
        column_output_buffers.push_back(column_buffer);
        column_output_offsets.push_back(0);
        
        DEBUG_OUT << "Column " << col_idx << ": " << total_output_size << " bytes output" << std::endl;
    }
    
    setup_start = std::chrono::high_resolution_clock::now();
    
    for (size_t i = 0; i < row_groups.size(); i++)
    {
        for (size_t col_idx = 0; col_idx < row_groups[i].columns.size(); col_idx++) {
            int core_idx = column_to_core_mapping[col_idx];
            for (size_t j = 0; j < row_groups[i].columns[col_idx].pages.size(); j++)
            {
                struct common::page_info_compact& page = row_groups[i].columns[col_idx].pages[j];
                int64_t config = common::generateConfig(&page, row_groups[i].columns[col_idx].dictionary && j == (row_groups[i].columns[col_idx].pages.size() - 1), jump_header, simulate_compression);
                common::writeConfigToFPGA(&cthread, config, core_idx);

                uint32_t in_size = jump_header ? page.compressed_page_size : page.compressed_page_size + page.header_size;
                // void *data = cthread.getMem({COYOTE_ALLOC_TYPE, in_size});
                // std::memcpy(data, file_data + page.fileOffset + (jump_header ? page.header_size : 0), in_size);
                
                size_t in_data_offset = page.fileOffset + (jump_header ? page.header_size : 0);
                page.in_data = static_cast<char*>(in_data) + in_data_offset;

                // Track input data size
                total_input_transferred_core[core_idx] += in_size;

                // Debug printing of input data for FPGA waveform viewer
                DEBUG_OUT << "=== INPUT DATA DEBUG ===" << std::dec<< std::endl;
                DEBUG_OUT << "Row Group: " << i << ", Column: " << col_idx << ", Page: " << j << std::endl;
                DEBUG_OUT << "Page Type: " << (page.type == parquet_thrift::format::PageType::DATA_PAGE ? "DATA_PAGE" : "DICT_PAGE") << std::endl;
                DEBUG_OUT << "Input Size: " << in_size << " bytes" << std::endl;
                DEBUG_OUT << "Data (512 bits per line):" << std::endl;
                
                // Print hex data with 512 bits (64 bytes) per line
                const uint8_t* byte_data = static_cast<const uint8_t*>(page.in_data);
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
                DEBUG_OUT << "============================" << std::endl;

                // Invoke input transfer with chunking
                int input_transfers = common::invokeWithChunking(&cthread, coyote::CoyoteOper::LOCAL_READ, page.in_data, in_size, true, core_idx);

                if (page.type == parquet_thrift::format::PageType::DATA_PAGE) {
                    uint32_t out_size = common::calculateOutputSize(page);
                    
                    // Use offset pointer into the pre-allocated column buffer
                    void *out_data = static_cast<char*>(column_output_buffers[col_idx]) + column_output_offsets[col_idx];
                    
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
    DEBUG_OUT << "Processing " << total_writes << " total writes..." << std::endl;
    
    completion_start = std::chrono::high_resolution_clock::now();
    while (cthread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) < total_writes) {
        auto end = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double> time = end - completion_start;
        if (time.count() > 10) {
            std::cerr << "Timeout, " << cthread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " of " << total_writes <<
                " at " << cthread.getCSR(static_cast<uint32_t>(common::CtrlRegs::OUT_CHUNK_CNT_REG)) << " output chunks" << std::endl;
            return 1;
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
    
    // Calculate timing durations
    auto overall_time = std::chrono::duration_cast<std::chrono::milliseconds>(overall_end - overall_start) / 1000.0;
    auto processing_time = std::chrono::duration_cast<std::chrono::milliseconds>(completion_end - setup_start) / 1000.0;
    auto memory_time = std::chrono::duration_cast<std::chrono::milliseconds>(memory_end - memory_start) / 1000.0;
    auto coyote_memory_time = std::chrono::duration_cast<std::chrono::milliseconds>(setup_start - memory_end) / 1000.0;
    auto setup_time = std::chrono::duration_cast<std::chrono::milliseconds>(completion_start - setup_start) / 1000.0;
    auto completion_time = std::chrono::duration_cast<std::chrono::milliseconds>(completion_end - completion_start) / 1000.0;

    
    DEBUG_OUT << std::dec; // Reset to decimal format
    DEBUG_OUT << "Timing Summary:" << std::endl;
    DEBUG_OUT << "  Overall time: " << std::fixed << std::setprecision(6) << overall_time.count() << "s" << std::endl;
    DEBUG_OUT << "  Processing time: " << std::fixed << std::setprecision(6) << processing_time.count() << "s" << std::endl;
    DEBUG_OUT << "  Memory/file operations: " << std::fixed << std::setprecision(6) << memory_time.count() << "s" << std::endl;
    DEBUG_OUT << "  Coyote memory transfer time: " << std::fixed << std::setprecision(6) << coyote_memory_time.count() << "s" << std::endl;
    DEBUG_OUT << "  Setup time (non-blocking): " << std::fixed << std::setprecision(6) << setup_time.count() << "s" << std::endl;
    DEBUG_OUT << "  Completion wait time: " << std::fixed << std::setprecision(6) << completion_time.count() << "s" << std::endl;
    
    size_t total_input_transferred = 0;
    size_t total_output_transferred = 0;
    for (int t = 0; t < num_units; t++) {
        total_input_transferred += total_input_transferred_core[t];
        total_output_transferred += total_output_transferred_core[t];
    }
    DEBUG_OUT << "Data Size Summary:" << std::endl;
    DEBUG_OUT << "  Parquet file size: " << file_size << " bytes (" << std::fixed << std::setprecision(2) << (file_size / (1024.0 * 1024.0)) << " MB)" << std::endl;
    DEBUG_OUT << "  Total input transferred: " << total_input_transferred << " bytes (" << std::fixed << std::setprecision(2) << (total_input_transferred / (1024.0 * 1024.0)) << " MB)" << std::endl;
    DEBUG_OUT << "  Total output transferred: " << total_output_transferred << " bytes (" << std::fixed << std::setprecision(2) << (total_output_transferred / (1024.0 * 1024.0)) << " MB)" << std::endl;
    
    DEBUG_OUT << "Throughput Metrics:" << std::endl;
    // max of cycles_total
    for (int t = 0; t < num_units; t++) {

        DEBUG_OUT << "  Core " << t << ": " << core_cycles_total[t] << " total, " << core_cycles_output_stalled[t] << " output stalled cycles, " << core_cycles_input_stalled[t] << " input stalled cycles" << std::endl;
        DEBUG_OUT << "  Input throughput: " << std::fixed << std::setprecision(2) 
                << (total_input_transferred_core[t] / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
                << ", " << std::setprecision(2) << (static_cast<double>(total_input_transferred_core[t]) / core_cycles_total[t]) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_input_transferred_core[t]) / core_cycles_total[t]) / 4 << " GB/s" << std::endl;
        DEBUG_OUT << "  Output throughput: " << std::fixed << std::setprecision(2) 
                << (total_output_transferred_core[t] / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
                << ", "  << std::setprecision(2) << (static_cast<double>(total_output_transferred_core[t]) / core_cycles_total[t]) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_output_transferred_core[t]) / core_cycles_total[t]) / 4 << " GB/s" << std::endl;
    }
    DEBUG_OUT << "  Final: " << total_cycles_total << " total" << std::endl;
    DEBUG_OUT << "  Input throughput: " << std::fixed << std::setprecision(2) 
            << (total_input_transferred / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
            << ", " << std::setprecision(2) << (static_cast<double>(total_input_transferred) / total_cycles_total) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_input_transferred) / total_cycles_total) / 4 << " GB/s" << std::endl;
    DEBUG_OUT << "  Output throughput: " << std::fixed << std::setprecision(2) 
            << (total_output_transferred / (1024.0 * 1024.0 * processing_time.count())) << " MB/s"
            << ", "  << std::setprecision(2) << (static_cast<double>(total_output_transferred) / total_cycles_total) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_output_transferred) / total_cycles_total) / 4 << " GB/s" << std::endl;

    DEBUG_OUT << "Performance Ratios:" << std::endl;
    DEBUG_OUT << "  Compression ratio: " << std::fixed << std::setprecision(2) 
              << (static_cast<double>(total_output_transferred) / total_input_transferred) << "x" << std::endl;
    DEBUG_OUT << "  File utilization: " << std::fixed << std::setprecision(1) 
              << (static_cast<double>(total_input_transferred) / file_size * 100.0) << "%" << std::endl;
    
    
    // CSV output for easy plotting
    // DEBUG_OUT << "\nCSV_PERFORMANCE_DATA:" << std::endl;
    // DEBUG_OUT << "file_size_bytes,input_transferred_bytes,output_transferred_bytes,data_processed_bytes,"
    //           << "completion_time_seconds,input_mbps,output_mbps,effective_mbps,cycles_total,cycles_stalled" << std::endl;
    // DEBUG_OUT << file_size << "," << total_input_transferred << "," << total_output_transferred << "," << total_data_processed << ","
    //           << std::fixed << std::setprecision(6) << completion_time.count() << ","
    //           << std::fixed << std::setprecision(2) << (total_input_transferred / (1024.0 * 1024.0 * completion_time.count())) << ","
    //           << std::fixed << std::setprecision(2) << (total_output_transferred / (1024.0 * 1024.0 * completion_time.count())) << ","
    //           << std::fixed << std::setprecision(2) << (total_data_processed / (1024.0 * 1024.0 * completion_time.count())) << ","
    //           << cycles_total << "," << cycles_stalled << std::endl;
    
    // Reset performance counters and clear completion status for all threads
    cthread.clearCompleted();


    // Debug printing
    if (print_mode != PrintMode::NONE) {
        for (size_t col_idx = 0; col_idx < row_groups[0].columns.size(); col_idx++) {
            DEBUG_OUT << "Column " << col_idx << ": [";
            
            // Calculate total size for this column across all row groups
            size_t total_column_size = 0;
            for (size_t i = 0; i < row_groups.size(); i++) {
                total_column_size += row_groups[i].columns[col_idx].num_values * row_groups[i].columns[col_idx].byteWidth;
            }
            
            // Print the entire column buffer based on print mode
            if (total_column_size > 0) {
                if (print_mode == PrintMode::HEX) {
                    common::printBufferHex(column_output_buffers[col_idx], total_column_size, row_groups[0].columns[col_idx].byteWidth);
                } else if (print_mode == PrintMode::VALUES) {
                    bool use_formatting = (format_mode == FormattingMode::FORMATTED);
                    common::printBuffer(column_output_buffers[col_idx], total_column_size, row_groups[0].columns[col_idx].byteWidth, 
                                       32, false, 1050, "binary", "little", DEBUG_OUT, row_groups[0].columns[col_idx].physical_type, use_formatting);
                }
            }
            
            DEBUG_OUT << "]" << std::dec << std::endl;
        }
    }

    // Sleep for 1 second
    std::this_thread::sleep_for(std::chrono::seconds(1));
    }

}
