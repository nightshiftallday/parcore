#include "metadata.hpp"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>

using namespace parcore::metadata;

void read_metadata(std::string &file) {
  std::ifstream in(file, std::ios::binary);
  if (!in) {
    throw std::runtime_error("could not open metadata file at: " + file);
  }

  Metadata meta = Metadata::from(in);
  for (size_t i = 0; i < meta.groups.size(); ++i) {
    auto rg = meta.groups[i];
    for (size_t j = 0; j < rg.chunks.size(); ++j) {
      auto chunk = rg.chunks[j];
      std::cout << i << ":" << j << " " << chunk.num_values << " " << chunk.type
                << " " << chunk.compression << std::endl;

      if (chunk.dictionary != std::nullopt) {
        auto page = *chunk.dictionary;
        std::cout << i << ":" << j << ":dict " << page.offset << " "
                  << page.size << " " << page.encoding << std::endl;
      }

      auto page = chunk.data;
      std::cout << i << ":" << j << ":data " << page.offset << " " << page.size
                << " " << page.encoding << std::endl;
    }
  }
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    std::cerr << "usage: " << argv[0] << "<file.parquet.meta>" << std::endl;
    return 1;
  }

  std::string file = argv[1];
  read_metadata(file);
  return 0;
}
