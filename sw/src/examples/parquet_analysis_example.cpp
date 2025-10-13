#include <iostream>
#include <iomanip>
#include <cstdlib>
#include "common.h"

void printRowGroupInfo(const std::vector<struct common::row_group_info_compact>& row_groups) {
    std::cout << "\n=== PARQUET FILE ANALYSIS RESULTS ===" << std::endl;
    std::cout << "Number of row groups: " << row_groups.size() << std::endl;
    
    for (size_t rg_idx = 0; rg_idx < row_groups.size(); ++rg_idx) {
        const auto& rg = row_groups[rg_idx];
        
        std::cout << "\n--- Row Group " << rg_idx << " (ordinal: " << rg.ordinal << ") ---" << std::endl;
        std::cout << "  Rows: " << rg.num_rows << std::endl;
        std::cout << "  Total byte size: " << rg.total_byte_size << " bytes" << std::endl;
        std::cout << "  Total compressed size: " << rg.total_compressed_size << " bytes" << std::endl;
        std::cout << "  Compression ratio: " << std::fixed << std::setprecision(2) 
                  << (double)rg.total_compressed_size / rg.total_byte_size * 100 << "%" << std::endl;
        std::cout << "  Number of columns: " << rg.columns.size() << std::endl;
        
        for (size_t col_idx = 0; col_idx < rg.columns.size(); ++col_idx) {
            const auto& col = rg.columns[col_idx];
            
            std::cout << "\n    Column " << col_idx << ":" << std::endl;
            std::cout << "      Physical type: " << col.physical_type << std::endl;
            std::cout << "      Byte width: " << col.byteWidth << std::endl;
            std::cout << "      Total compressed size: " << col.total_compressed_size << " bytes" << std::endl;
            std::cout << "      Total uncompressed size: " << col.total_uncompressed_size << " bytes" << std::endl;
            std::cout << "      Number of pages: " << col.pages.size() << std::endl;
            std::cout << "      Compression codec: " << col.compression << std::endl;
            
            // Show first few pages for detailed inspection
            size_t max_pages_to_show = std::min(static_cast<size_t>(3), col.pages.size());
            if (max_pages_to_show > 0) {
                std::cout << "      First " << max_pages_to_show << " page(s):" << std::endl;
                for (size_t page_idx = 0; page_idx < max_pages_to_show; ++page_idx) {
                    const auto& page = col.pages[page_idx];
                    std::cout << "        Page " << page_idx << ":" << std::endl;
                    std::cout << "          Type: " << static_cast<int>(page.type) << std::endl;
                    std::cout << "          Uncompressed size: " << page.uncompressed_page_size << " bytes" << std::endl;
                    std::cout << "          Compressed size: " << page.compressed_page_size << " bytes" << std::endl;
                    std::cout << "          Num values: " << page.num_values << std::endl;
                    std::cout << "          Encoding: " << static_cast<int>(page.encoding) << std::endl;
                    std::cout << "          Data offset: " << page.fileOffset << std::endl;
                }
                if (col.pages.size() > max_pages_to_show) {
                    std::cout << "        ... and " << (col.pages.size() - max_pages_to_show) 
                              << " more page(s)" << std::endl;
                }
            }
        }
    }
    
    std::cout << "\n=== END ANALYSIS ===" << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <parquet-file>" << std::endl;
        std::cerr << "Example: " << argv[0] << " data.parquet" << std::endl;
        std::cerr << std::endl;
        std::cerr << "This example demonstrates how to use common::analyseParquetFile" << std::endl;
        std::cerr << "to analyze a parquet file and print detailed information about" << std::endl;
        std::cerr << "its structure, including row groups, columns, and pages." << std::endl;
        return 1;
    }
    
    const std::string filepath = argv[1];
    
    try {
        std::cout << "Analyzing parquet file: " << filepath << std::endl;
        std::cout << "Using common::analyseParquetFile function..." << std::endl;
        
        // Call the analyseParquetFile function with debug output to console
        std::vector<struct common::row_group_info_compact> row_groups = 
            common::analyseParquetFile(filepath, std::cout);
        
        // Print the detailed analysis results
        std::cout << common::toString(row_groups);
        
        std::cout << "\nAnalysis completed successfully!" << std::endl;
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    
    return 0;
}
