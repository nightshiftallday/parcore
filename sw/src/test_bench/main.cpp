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
#include <iostream>
#include <iomanip>
#include <sstream>

void printTimingResult(const std::string& reader_type, const common::parquet_timing_result& result) {
    std::cout << "\n=== " << reader_type << " Reader Results ===" << std::endl;
    std::cout << "Filename: " << result.filename << std::endl;
    std::cout << "Total time: " << std::fixed << std::setprecision(3) << result.total_time_milliseconds << " ms" << std::endl;
    std::cout << "File size: " << result.file_size_bytes << " bytes (" << std::fixed << std::setprecision(2) << (result.file_size_bytes / 1024.0 / 1024.0) << " MB)" << std::endl;
    std::cout << "Output size: " << result.output_size_bytes << " bytes (" << std::fixed << std::setprecision(2) << (result.output_size_bytes / 1024.0 / 1024.0) << " MB)" << std::endl;
    std::cout << "Memory transfer time: " << std::fixed << std::setprecision(3) << result.memory_transfer_time_milliseconds << " ms" << std::endl;
    std::cout << "Number of rows: " << result.num_rows << std::endl;
    std::cout << "Number of columns: " << result.num_columns << std::endl;

    std::cout << "Time breakdown:" << std::endl;
    std::cout << "  Overall time: " << std::fixed << std::setprecision(3) << result.total_time_milliseconds << " ms" << std::endl;
    std::cout << "  Processing time: " << std::fixed << std::setprecision(3) << result.processing_time_milliseconds << " ms" << std::endl;
    std::cout << "  Memory transfer time: " << std::fixed << std::setprecision(3) << result.memory_transfer_time_milliseconds << " ms" << std::endl;
    std::cout << "  Coyote memory transfer time: " << std::fixed << std::setprecision(3) << result.coyote_memory_transfer_time_milliseconds << " ms" << std::endl;
    std::cout << "  Setup time (non-blocking): " << std::fixed << std::setprecision(3) << result.setup_time_milliseconds << " ms" << std::endl;
    std::cout << "  Completion time: " << std::fixed << std::setprecision(3) << result.completion_time_milliseconds << " ms" << std::endl;
    
    size_t total_input_transferred = 0;
    size_t total_output_transferred = 0;
    size_t total_header_transferred = 0;
    for (int t = 0; t < result.core_cycles_total.size(); t++) {
        total_input_transferred += result.total_input_transferred[t];
        total_output_transferred += result.total_output_transferred[t];
        total_header_transferred += result.total_header_transferred[t];
        std::cout << "Core " << t << " cycles total: " << result.core_cycles_total[t] << std::endl;
        std::cout << "Core " << t << " cycles output stalled: " << result.core_cycles_output_stalled[t] << std::endl;
        std::cout << "Core " << t << " cycles input stalled: " << result.core_cycles_input_stalled[t] << std::endl;
        std::cout << "Core " << t << " input throughput: " << std::fixed << std::setprecision(2) 
            << (result.total_input_transferred[t] / (1024.0 * 1024.0 * result.processing_time_milliseconds)) / 1000.0 << " MB/s"
            << ", "  << std::setprecision(2) << (static_cast<double>(result.total_input_transferred[t]) / result.core_cycles_total[t]) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(result.total_input_transferred[t]) / result.core_cycles_total[t]) / 4 << " GB/s" << std::endl;
        std::cout << "Core " << t << " output throughput: " << std::fixed << std::setprecision(2) 
            << (result.total_output_transferred[t] / (1024.0 * 1024.0 * result.processing_time_milliseconds)) / 1000.0 << " MB/s"
            << ", "  << std::setprecision(2) << (static_cast<double>(result.total_output_transferred[t]) / result.core_cycles_total[t]) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(result.total_output_transferred[t]) / result.core_cycles_total[t]) / 4 << " GB/s" << std::endl;
        std::cout << "Core " << t << " header throughput: " << std::fixed << std::setprecision(2) 
            << (result.total_header_transferred[t] / (1024.0 * 1024.0 * result.processing_time_milliseconds)) / 1000.0 << " MB/s"
            << ", "  << std::setprecision(2) << (static_cast<double>(result.total_header_transferred[t]) / result.core_cycles_total[t]) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(result.total_header_transferred[t]) / result.core_cycles_total[t]) / 4 << " GB/s" << std::endl;
    }
    std::cout << "Total input transferred: " << total_input_transferred << " bytes" << std::endl;
    std::cout << "Total output transferred: " << total_output_transferred << " bytes" << std::endl;
    std::cout << "Total header transferred: " << total_header_transferred << " bytes" << std::endl;
    std::cout << "Total cycles total: " << result.total_cycles_total << std::endl;
    if (result.processing_time_milliseconds > 0) {
        // Calculate and display throughput
        std::cout << "Total input throughput: " << std::fixed << std::setprecision(2) 
            << (total_input_transferred / (1024.0 * 1024.0 * result.processing_time_milliseconds)) / 1000.0 << " MB/s"
            << ", "  << std::setprecision(2) << (static_cast<double>(total_input_transferred) / result.total_cycles_total) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_input_transferred) / result.total_cycles_total) / 4 << " GB/s" << std::endl;
        std::cout << "Total output throughput: " << std::fixed << std::setprecision(2) 
            << (total_output_transferred / (1024.0 * 1024.0 * result.processing_time_milliseconds)) / 1000.0 << " MB/s"
            << ", "  << std::setprecision(2) << (static_cast<double>(total_output_transferred) / result.total_cycles_total) << " bytes/cycle => " << std::setprecision(2) << (static_cast<double>(total_output_transferred) / result.total_cycles_total) / 4 << " GB/s" << std::endl;
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <parquet-file> [--excluded-columns <col1,col2,col3,...>] [--num-units <N>] [--simulate-compression] [--jump-header]" << std::endl;
        return 1;
    }
    std::string file_name = argv[1];
    bool simulate_compression = false;
    int num_units = 1;
    std::vector<int> excluded_columns;
    bool jump_header = true;

    for (int i = 2; i < argc; i++) {
        if (std::string(argv[i]) == "--simulate-compression") {
            simulate_compression = true; // Don't jump header when flag is present
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
        } else if (std::string(argv[i]) == "--excluded-columns") {
            if (i + 1 < argc) {
                std::string excluded_columns_str = argv[i + 1];
                std::stringstream ss(excluded_columns_str);
                std::string item;
                
                while (std::getline(ss, item, ',')) {
                    try {
                        int col_idx = std::stoi(item);
                        if (col_idx < 0) {
                            std::cerr << "Error: column indices must be non-negative" << std::endl;
                            return 1;
                        }
                        excluded_columns.push_back(col_idx);
                    } catch (const std::exception& e) {
                        std::cerr << "Error: invalid column index '" << item << "'" << std::endl;
                        return 1;
                    }
                }
                
                if (excluded_columns.empty()) {
                    std::cerr << "Error: --columns requires at least one column index" << std::endl;
                    return 1;
                }
                
                i++; // Skip the next argument since it's the column list
            } else {
                std::cerr << "Error: --columns requires a comma-separated list of column indices" << std::endl;
                return 1;
            }
        } else if (std::string(argv[i]) == "--jump-header") {
            jump_header = false; // Don't jump header when flag is present
        }
    }

    std::cout << "Parquet Reader Benchmark" << std::endl;
    std::cout << "========================" << std::endl;
    std::cout << "File: " << file_name << std::endl;
    
    if (!excluded_columns.empty()) {
        std::cout << "Excluded columns: ";
        for (size_t i = 0; i < excluded_columns.size(); ++i) {
            if (i > 0) std::cout << ", ";
            std::cout << excluded_columns[i];
        }
        std::cout << std::endl;
    }

    try {
        // Test CPU reader
        std::cout << "\nTesting CPU reader..." << std::endl;
        std::shared_ptr<arrow::Table> cpu_table;
        auto cpu_result = common::loadParquetFileCPU(file_name, cpu_table);
        
        if (cpu_table) {
            std::cout << "CPU table schema:" << std::endl;
            std::cout << cpu_table->schema()->ToString() << std::endl;
        }

        if (simulate_compression) {
            std::cout << "Simulating compression..." << std::endl;
            size_t pos = file_name.find("_snappy");
            if (pos != std::string::npos) {
                file_name = file_name.substr(0, pos) + ".parquet";
            }
            std::cout << "Uncompressed file name: " << file_name << std::endl;
        }

        // Test FPGA reader
        std::cout << "\nTesting FPGA reader..." << std::endl;
        std::shared_ptr<arrow::Table> fpga_table;
        auto fpga_result = common::loadParquetFileFPGA(file_name, fpga_table, excluded_columns, jump_header, num_units, simulate_compression);
        
        // if (fpga_table) {
        //     std::cout << "FPGA table schema:" << std::endl;
        //     std::cout << fpga_table->schema()->ToString() << std::endl;
        // }
        printTimingResult("CPU", cpu_result);
        printTimingResult("FPGA", fpga_result);

        // Compare results
        std::cout << "\n=== Performance Comparison ===" << std::endl;
        if (cpu_result.total_time_milliseconds > 0 && fpga_result.processing_time_milliseconds > 0) {
            double speedup = cpu_result.total_time_milliseconds / fpga_result.processing_time_milliseconds;
            double speedup_withCoyoteMemory = cpu_result.total_time_milliseconds / (fpga_result.processing_time_milliseconds + fpga_result.coyote_memory_transfer_time_milliseconds);
            std::cout << "FPGA speedup: " << std::fixed << std::setprecision(2) << speedup << "x" << std::endl;
            std::cout << "FPGA speedup with Coyote memory: " << std::fixed << std::setprecision(2) << speedup_withCoyoteMemory << "x" << std::endl;
            
            if (speedup > 1.0) {
                std::cout << "FPGA is " << std::fixed << std::setprecision(1) << ((speedup - 1.0) * 100.0) << "% faster than CPU" << std::endl;
                std::cout << "FPGA with Coyote memory is " << std::fixed << std::setprecision(1) << ((speedup_withCoyoteMemory - 1.0) * 100.0) << "% faster than CPU" << std::endl;
            } else {
                std::cout << "CPU is " << std::fixed << std::setprecision(1) << ((1.0/speedup - 1.0) * 100.0) << "% faster than FPGA" << std::endl;
                std::cout << "CPU is " << std::fixed << std::setprecision(1) << ((1.0/speedup_withCoyoteMemory - 1.0) * 100.0) << "% faster than FPGA with Coyote memory" << std::endl;
            }
        }

        // Verify data consistency (basic check)
        if (cpu_table && fpga_table) {
            std::cout << "\n=== Data Consistency Check ===" << std::endl;
            bool same_dimensions = (cpu_table->num_rows() == fpga_table->num_rows()) && 
                                  (cpu_table->num_columns() == fpga_table->num_columns());
            std::cout << "Same dimensions: " << (same_dimensions ? "YES" : "NO") << std::endl;
            
            if (same_dimensions) {
                std::cout << "Both tables have " << cpu_table->num_rows() << " rows and " << cpu_table->num_columns() << " columns" << std::endl;
            } else {
                std::cout << "CPU table: " << cpu_table->num_rows() << " rows, " << cpu_table->num_columns() << " columns" << std::endl;
                std::cout << "FPGA table: " << fpga_table->num_rows() << " rows, " << fpga_table->num_columns() << " columns" << std::endl;
            }
        }

        // Output CSV line for FPGA test case (as requested by user)
        std::cout << "\n=== CSV Output for FPGA Test Case ===" << std::endl;
        
        // Extract name from filename (remove path and extension)
        std::string base_name = fpga_result.filename;
        size_t dot_pos = base_name.find_last_of('.');
        if (dot_pos != std::string::npos) {
            base_name = base_name.substr(0, dot_pos);
        }
        // Filename components: ..._dictsize_dtype_dict_snappy
        // if _dict is present use_dict = 1, otherwise use_dict = 0
        // if _snappy is present compression_type = 1, otherwise compression_type = 0
        // dtype is part of the filename
        // dictsize is part of the filename
        
        // Determine data type, is part of the filename
        std::vector<std::string> filename_components;
        std::stringstream ss(base_name);
        std::string component;
        while (std::getline(ss, component, '_')) {
            filename_components.push_back(component);
        }
        
        std::string dtype = "int32"; // Default
        std::string dictsize = "0";  // Default
        if (filename_components.size() > 3) {
            dictsize = filename_components[3];
        }
        if (filename_components.size() > 4) {
            dtype = filename_components[4];
        }
        std::string compression_type = "none"; // 0 for no compression
        std::string use_dict = "plain"; // Default to no dictionary
        for (std::string component : filename_components) {
            if (component == "dict") {
                use_dict = "dict";
            }
            if (component == "snappy") {
                compression_type = "snappy";
            }
        }
        
        // Calculate totals from vectors
        size_t total_input_transferred = 0;
        size_t total_header_transferred = 0; 
        size_t total_output_transferred = 0;
        size_t total_cycles = 0;
        size_t total_cycles_output_stalled = 0;
        size_t total_cycles_input_stalled = 0;
        
        for (size_t i = 0; i < fpga_result.total_input_transferred.size(); i++) {
            total_input_transferred += fpga_result.total_input_transferred[i];
        }
        for (size_t i = 0; i < fpga_result.total_header_transferred.size(); i++) {
            total_header_transferred += fpga_result.total_header_transferred[i];
        }
        for (size_t i = 0; i < fpga_result.total_output_transferred.size(); i++) {
            total_output_transferred += fpga_result.total_output_transferred[i];
        }
        for (size_t i = 0; i < fpga_result.core_cycles_total.size(); i++) {
            total_cycles += fpga_result.core_cycles_total[i];
        }
        for (size_t i = 0; i < fpga_result.core_cycles_output_stalled.size(); i++) {
            total_cycles_output_stalled += fpga_result.core_cycles_output_stalled[i];
        }
        for (size_t i = 0; i < fpga_result.core_cycles_input_stalled.size(); i++) {
            total_cycles_input_stalled += fpga_result.core_cycles_input_stalled[i];
        }
        
        // Calculate compression ratio and file utilization
        double compression_ratio = total_input_transferred > 0 ? 
            static_cast<double>(total_output_transferred) / static_cast<double>(total_input_transferred) : 1.0;
        double file_utilization = fpga_result.file_size_bytes > 0 ? 
            (static_cast<double>(total_input_transferred) / static_cast<double>(fpga_result.file_size_bytes)) * 100.0 : 0.0;
        double header_transfer_ratio = total_input_transferred > 0 ? 
            (static_cast<double>(total_header_transferred) / static_cast<double>(total_input_transferred)) * 100.0 : 0.0;
        
        // Output CSV line matching the expected format (without timing information as requested)
        // name, dtype, compression, use_dict, input_throughput, output_throughput, file_size, output_size, num_rows, cycles, cycles_output_stalled, cycles_input_stalled, input_transferred, header_transferred, output_transferred, compression_ratio, file_utilization
        std::cout << "Copy this line to your CSV:" << std::endl;
        std::cout << dtype << ","
                  << compression_type << ","
                  << use_dict << ","
                  << dictsize << ","
                  << std::setprecision(2) << (static_cast<double>(total_input_transferred) / total_cycles) / 4 << ","  // input_throughput (no timing info requested)
                  << std::setprecision(2) << (static_cast<double>(total_output_transferred) / total_cycles) / 4 << ","  // output_throughput (no timing info requested)
                  << fpga_result.file_size_bytes << ","
                  << fpga_result.output_size_bytes << ","
                  << fpga_result.num_rows << ","
                  << total_cycles << ","
                  << total_cycles_output_stalled << ","
                  << total_cycles_input_stalled << ","
                  << total_input_transferred << ","
                  << total_header_transferred << ","
                  << total_output_transferred << ","
                  << std::fixed << std::setprecision(1) << compression_ratio << ","
                  << std::fixed << std::setprecision(1) << file_utilization << ","
                  << std::fixed << std::setprecision(1) << header_transfer_ratio << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
