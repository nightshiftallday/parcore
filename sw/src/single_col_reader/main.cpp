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
#include <fstream>
#include <memory>
#include <cstdlib>
#include <any>
#include <cassert>
#include <thrift/protocol/TCompactProtocol.h>
#include <thrift/transport/TBufferTransports.h>
 
#include "cThread.hpp"

// Local structures for legacy single_col_reader (deprecated - use compact versions instead)
namespace legacy {
    struct page {
        parquet_thrift::format::PageHeader page_header;
        void *in_data;
        void *out_data;
    };

    struct row_group {
        std::vector<struct page> pages;
        bool dictionary;
    };
}

// Deprecated, use 'simulation' binary or 'common' functions instead for current functionality.
int main(int argc, char *argv[]) {
    std::cerr << "WARNING: single_col_reader is DEPRECATED. Use 'simulation' binary instead for current functionality." << std::endl;
    std::cerr << "This program uses legacy structures and may be removed in future versions." << std::endl;
    
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <parquet-file> <out-byte-width>" << std::endl;
        return 1;
    }
    const std::string file_name = argv[1];
    size_t out_byte_width = std::stoi(argv[2]);
    uint32_t compression = std::stoi(argv[3]);

    // Open Parquet metadata
    std::unique_ptr<parquet::ParquetFileReader> reader = parquet::ParquetFileReader::OpenFile(file_name, false);
    std::shared_ptr<parquet::FileMetaData> metadata = reader->metadata();
    uint32_t num_row_groups = metadata->num_row_groups();
    uint64_t num_rows = metadata->num_rows();
    assert(metadata->num_columns() == 1);

    // Open binary Parquet file, read size and content into char array
    std::ifstream file(file_name, std::ios::ate | std::ios::binary);
    if (!file) {
        std::cerr << "Cannot open file " << file_name << std::endl;
        return 1;
    }
    std::streampos file_size = file.tellg();
    file.seekg(0, std::ios::beg);
    char *file_data = (char *) malloc(file_size);
    file.read(file_data, file_size);
    DEBUG_OUT << "opened file, size: " << file_size << std::endl;

    // Initialize cThread
    std::unique_ptr<coyote::cThread> cthread(new coyote::cThread(0, getpid(), 0));

    // Read file structure from metadata and copy data sections to mapped memory.
    std::vector<struct legacy::row_group> row_groups(num_row_groups);
    uint32_t data_pages = 0;
    for (int i = 0; i < num_row_groups; i++) {
        row_groups[i].dictionary = metadata->RowGroup(i)->ColumnChunk(0)->has_dictionary_page();
        DEBUG_OUT << "row group " << i << ", dictionary: " << row_groups[i].dictionary << std::endl;
        int j = row_groups[i].dictionary 
            ? metadata->RowGroup(i)->ColumnChunk(0)->dictionary_page_offset()
            : metadata->RowGroup(i)->ColumnChunk(0)->data_page_offset();
        
        parquet_thrift::format::PageHeader page_header;
        for (; ; j += page_header.compressed_page_size) {
            DEBUG_OUT << "header start at " << j << std::endl;
            try {
                // Read header length and compressed size of data page
                auto buf = std::make_shared<apache::thrift::transport::TMemoryBuffer>(
                    reinterpret_cast<uint8_t *>(file_data + j), file_size);
                j += buf->available_read();
                apache::thrift::protocol::TCompactProtocol protocol(buf);
                page_header.read(&protocol);
                j -= buf->available_read();
            } catch (const apache::thrift::TException& e) {
                break; // No header
            }
            assert((row_groups[i].pages.size() == 0 && page_header.type == parquet_thrift::format::PageType::DICTIONARY_PAGE)
                || (page_header.type == parquet_thrift::format::PageType::DATA_PAGE));

            void *data = cthread->getMem({coyote::CoyoteAllocType::HPF, page_header.compressed_page_size});
            std::memcpy(data, file_data + j, page_header.compressed_page_size);
            uint32_t out_size = page_header.data_page_header.encoding == parquet_thrift::format::Encoding::PLAIN
                ? page_header.uncompressed_page_size
                : page_header.data_page_header.num_values * out_byte_width;
            void *out_data = cthread->getMem({coyote::CoyoteAllocType::HPF, out_size});
            struct legacy::page page = {page_header, data, out_data};
            row_groups[i].pages.push_back(page);

            if (page_header.type == parquet_thrift::format::PageType::DATA_PAGE) {
                data_pages++;
            }

            DEBUG_OUT << "data start at " << j << std::endl;
            DEBUG_OUT << "page type: " << page_header.type << std::endl;
            DEBUG_OUT << "page in size: " << page_header.compressed_page_size << std::endl;
            DEBUG_OUT << std::endl;
        }
        DEBUG_OUT << "row group " << i << ", pages: " << row_groups[i].pages.size() << std::endl;
        DEBUG_OUT << std::endl;
    }
    reader->Close();
    file.close();
    free(file_data);

    // Initialize FPGA
                cthread->setCSR(0, static_cast<uint32_t>(common::CtrlRegs::PERF_RESET_REG));
    cthread->clearCompleted();

    // Start measurement
    auto start_time = std::chrono::high_resolution_clock::now();
    DEBUG_OUT << "start measuring" << std::endl;

    uint64_t cycles_total = 0, cycles_stalled = 0;
    int writes = 0;
    for (size_t i = 0; i < num_row_groups; i++) {
        // Start reads for all pages in order and writes for data pages
        DEBUG_OUT << "row group " << i << std::endl;
        size_t pages = row_groups[i].pages.size();
        for (size_t j = 0; j < pages; j++) {
            struct legacy::page& page = row_groups[i].pages[j];

            coyote::localSg sg_in = {page.in_data, page.page_header.compressed_page_size, coyote::STRM_HOST, 0};
            // memset(&sg_in, 0, sizeof(coyote::localSg));
            // sg_in.local.src_addr = page.in_data;
            // sg_in.local.src_len = page.page_header.compressed_page_size;
            // sg_in.local.src_stream = coyote::strmHost;
            cthread->invoke(coyote::CoyoteOper::LOCAL_READ, sg_in, false);

            if (page.page_header.type == parquet_thrift::format::PageType::DATA_PAGE) {
                uint32_t out_size = page.page_header.data_page_header.encoding == parquet_thrift::format::Encoding::PLAIN
                    ? page.page_header.uncompressed_page_size
                    : page.page_header.data_page_header.num_values * out_byte_width;
                
                coyote::localSg sg_out = {page.out_data, out_size, coyote::STRM_HOST, 0};
                // memset(&sg_out, 0, sizeof(coyote::localSg));
                // sg_out.local.dst_addr = page.out_data;
                // sg_out.local.dst_len = out_size;
                // sg_out.local.dst_stream = coyote::strmHost;
                cthread->invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_out, false);

                writes++;

                DEBUG_OUT << "data page " << j << ", compressed_size " << page.page_header.compressed_page_size << ", uncompressed_size " << page.page_header.uncompressed_page_size << ", num_rows " << page.page_header.data_page_header.num_values << std::endl;
            } else {
                DEBUG_OUT << "dict page " << j << ", compressed_size " << page.page_header.compressed_page_size << ", uncompressed_size " << page.page_header.uncompressed_page_size << ", num_rows " << page.page_header.dictionary_page_header.num_values << std::endl;
            }
        }

        // If a new dict needs to be written for next row group or at the end, wait for writes to complete and reset
        if ((i < num_row_groups-1 && row_groups[i+1].dictionary) || i == num_row_groups-1) {
            DEBUG_OUT << "waiting for " << writes << " writes to complete" << std::endl;
            auto start = std::chrono::high_resolution_clock::now();
            while (cthread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) < writes) {
                auto end = std::chrono::high_resolution_clock::now();
                std::chrono::duration<double> time = end - start;
                if (time.count() > 10) {
                    std::cerr << "Timeout, " << cthread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " of " << writes <<
                        " at " << cthread->getCSR(static_cast<uint32_t>(common::CtrlRegs::OUT_CHUNK_CNT_REG)) << " output chunks" << std::endl;
                    return 1;
                }
            }

            // Read cycles
            cycles_total += cthread->getCSR(static_cast<uint32_t>(common::CtrlRegs::TIMER_TOTAL_REG));
            cycles_stalled += cthread->getCSR(static_cast<uint32_t>(common::CtrlRegs::TIMER_OUTPUT_STALLED_REG));
            DEBUG_OUT << "cycles: " << cycles_total << " - " << cycles_stalled << std::endl;

            // Reset
            cthread->setCSR(0, static_cast<uint32_t>(common::CtrlRegs::PERF_RESET_REG));
            
            cthread->clearCompleted();
            writes = 0;
        }
    }

    // Stop measurement
    DEBUG_OUT << "stop measuring" << std::endl;
    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> time = end_time - start_time;

#ifdef DEBUG
    // Dump values to file
    std::filesystem::path path(file_name);
    std::string file_stem = path.stem().string();

    std::ofstream outfile(file_stem + "_output.txt");
    if (outfile) {
        for (size_t i = 0; i < num_row_groups; i++) {
            for (size_t j = 0; j < row_groups[i].pages.size(); j++) {
                struct legacy::page page = row_groups[i].pages[j];
                if (page.page_header.type == parquet_thrift::format::PageType::DICTIONARY_PAGE) {
                    continue;
                }

                for (size_t k = 0; k < page.page_header.data_page_header.num_values; k++) {
                    uint64_t val = 0;
                    uint8_t *tmp = static_cast<uint8_t *>(page.out_data);
                    for (size_t l = 0; l < out_byte_width; l++) {
                        val |= tmp[k*out_byte_width + l] << (l*8);
                    }
                    outfile << val << std::endl;
                }
            }
        }
        outfile.close();
    } else {
        std::cerr << "Error opening output file." << std::endl;
    }

    // Output random value as sanity check
    std::srand(std::time(0));
    int32_t idx = std::rand() % num_rows;
    DEBUG_OUT << "value at index " << idx << ": ";
    for (size_t i = 0; i < num_row_groups; i++) {
        for (size_t j = 0; j < row_groups[i].pages.size(); j++) {
            struct legacy::page page = row_groups[i].pages[j];
            if (page.page_header.type == parquet_thrift::format::PageType::DICTIONARY_PAGE) {
                continue;
            }

            if (idx < page.page_header.data_page_header.num_values) {
                uint64_t val = 0;
                uint8_t *tmp = static_cast<uint8_t *>(page.out_data);
                for (int k = 0; k < out_byte_width; k++) {
                    val |= tmp[idx*out_byte_width + k] << k*8;
                }
                DEBUG_OUT << val << std::endl;

                goto endloop;
            } else {
                idx -= page.page_header.data_page_header.num_values;
            }
        }
    }
endloop:
    cthread->printDebug();
#endif

    std::cout << std::time(nullptr) << "," // 0
        << file_name.substr(file_name.find_last_of("/\\") + 1) << "," // 1
        << file_size << "," // 2
        << num_rows << "," // 3
        << num_row_groups << "," // 4
        << data_pages << "," // 5
        << out_byte_width << "," // 6
        << time.count() << "," // 7
        << cycles_total << "," // 8
        << cycles_stalled << ","; // 9
        // CPU time // 10

    DEBUG_OUT << std::endl;
    return 0;
}
