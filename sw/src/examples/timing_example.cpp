#include <common.h>
#include <arrow/api.h>
#include <iostream>
#include <iomanip>

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <parquet_file>" << std::endl;
        return 1;
    }
    
    std::string file_path = argv[1];
    std::shared_ptr<arrow::Table> table;
    
    // Load parquet file with timing
    common::parquet_timing_result timing_result = common::loadParquetFileCPU(file_path, table);
    
    // Print timing results
    std::cout << "=== Parquet Loading Timing Results ===" << std::endl;
    std::cout << "Filename: " << timing_result.filename << std::endl;
    std::cout << "Total Loading Time: " << std::fixed << std::setprecision(3) 
              << timing_result.total_time_milliseconds << " ms" << std::endl;
    std::cout << "File Size: " << timing_result.file_size_bytes << " bytes" << std::endl;
    std::cout << "Output Size (in memory): " << timing_result.output_size_bytes << " bytes" << std::endl;
    std::cout << "Memory Transfer Time: " << std::fixed << std::setprecision(3) 
              << timing_result.memory_transfer_time_milliseconds << " ms" << std::endl;
    std::cout << "Number of Rows: " << timing_result.num_rows << std::endl;
    std::cout << "Number of Columns: " << timing_result.num_columns << std::endl;
    
    // Calculate some performance metrics
    if (timing_result.total_time_milliseconds > 0) {
        // Convert milliseconds to seconds for throughput calculation
        double time_seconds = timing_result.total_time_milliseconds / 1000.0;
        double throughput_mb_per_sec = (timing_result.file_size_bytes / (1024.0 * 1024.0)) / time_seconds;
        std::cout << "Throughput: " << std::fixed << std::setprecision(2) 
                  << throughput_mb_per_sec << " MB/s" << std::endl;
        
        if (timing_result.num_rows > 0) {
            double rows_per_sec = timing_result.num_rows / time_seconds;
            std::cout << "Rows per second: " << std::fixed << std::setprecision(0) 
                      << rows_per_sec << " rows/s" << std::endl;
        }
        
        if (timing_result.output_size_bytes > 0) {
            double compression_ratio = (double)timing_result.file_size_bytes / timing_result.output_size_bytes;
            std::cout << "Compression ratio: " << std::fixed << std::setprecision(2) 
                      << compression_ratio << ":1" << std::endl;
        }
    }
    
    if (table) {
        std::cout << "\nTable successfully loaded!" << std::endl;
        std::cout << "Schema:" << std::endl;
        std::cout << table->schema()->ToString() << std::endl;
    } else {
        std::cout << "\nError: Table was not loaded successfully!" << std::endl;
        return 1;
    }
    
    return 0;
}
