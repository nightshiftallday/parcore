#include "standalone_types.h"
#include "standalone_binary_io.h"
#include <iostream>
#include <iomanip>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <binary-file>" << std::endl;
        std::cerr << "Example: " << argv[0] << " data_pages.bin" << std::endl;
        return 1;
    }
    
    const std::string filename = argv[1];
    
    try {
        std::cout << "Loading standalone binary file: " << filename << std::endl;
        
        // Load the row groups from binary file using standalone types
        std::vector<standalone::row_group_info_compact> row_groups;
        parquet_pageinfo::load_row_groups_binary(filename, row_groups);
        
        std::cout << "Successfully loaded " << row_groups.size() << " row groups" << std::endl;
        std::cout << std::endl;
        
        // Print detailed information
        for (size_t i = 0; i < row_groups.size(); i++) {
            const auto& row_group = row_groups[i];
            std::cout << "Row Group " << i << ":" << std::endl;
            std::cout << "  Columns: " << row_group.columns.size() << std::endl;
            
            for (size_t c = 0; c < row_group.columns.size(); c++) {
                const auto& column = row_group.columns[c];
                std::cout << "  Column " << c << ":" << std::endl;
                std::cout << "    Path: ";
                for (size_t p = 0; p < column.path_in_schema.size(); p++) {
                    if (p > 0) std::cout << ".";
                    std::cout << column.path_in_schema[p];
                }
                std::cout << std::endl;
                std::cout << "    Dictionary: " << (column.dictionary ? "Yes" : "No") << std::endl;
                std::cout << "    Num Values: " << column.num_values << std::endl;
                std::cout << "    Total Uncompressed Size: " << column.total_uncompressed_size << " bytes" << std::endl;
                std::cout << "    Total Compressed Size: " << column.total_compressed_size << " bytes" << std::endl;
                if (column.total_uncompressed_size > 0) {
                    double compression_ratio = (1.0 - (double)column.total_compressed_size / column.total_uncompressed_size) * 100.0;
                    std::cout << "    Compression Ratio: " << std::fixed << std::setprecision(2) << compression_ratio << "%" << std::endl;
                }
                std::cout << "    Pages: " << column.pages.size() << std::endl;
                
                // Count page types
                int data_pages = 0, dict_pages = 0;
                for (const auto& page : column.pages) {
                    if (page.type == standalone::page_types::DATA_PAGE) data_pages++;
                    else if (page.type == standalone::page_types::DICTIONARY_PAGE) dict_pages++;
                }
                std::cout << "    Data Pages: " << data_pages << ", Dictionary Pages: " << dict_pages << std::endl;
                
                // Show first few pages in detail
                for (size_t p = 0; p < std::min(column.pages.size(), size_t(3)); p++) {
                    const auto& page = column.pages[p];
                    std::cout << "      Page " << p << ":" << std::endl;
                    std::cout << "        Type: " << parquet_pageinfo::get_page_type_string(page.type) << std::endl;
                    std::cout << "        Num Values: " << page.num_values << std::endl;
                    std::cout << "        Uncompressed Size: " << page.uncompressed_page_size << " bytes" << std::endl;
                    std::cout << "        Compressed Size: " << page.compressed_page_size << " bytes" << std::endl;
                    std::cout << "        Header Size: " << page.header_size << " bytes" << std::endl;
                    std::cout << "        File Offset: " << page.fileOffset << std::endl;
                    std::cout << "        Encoding: " << parquet_pageinfo::get_encoding_string(page.encoding) << std::endl;
                    std::cout << "        Compression: " << parquet_pageinfo::get_compression_string(page.compression) << std::endl;
                    std::cout << "        Has Definition Levels: " << (page.isDefSet ? "Yes" : "No") << std::endl;
                    std::cout << "        Has Repetition Levels: " << (page.isRefSet ? "Yes" : "No") << std::endl;
                    std::cout << "        Byte Width: " << page.byteWidth << std::endl;
                }
                if (column.pages.size() > 3) {
                    std::cout << "        ... and " << (column.pages.size() - 3) << " more pages" << std::endl;
                }
                std::cout << std::endl;
            }
            std::cout << std::endl;
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    
    return 0;
} 