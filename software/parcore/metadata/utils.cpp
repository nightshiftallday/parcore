#include <parcore/metadata/utils.hpp>

#include <fstream>

namespace parcore {
namespace metadata {

Metadata from_file(const std::string &path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    throw std::runtime_error("could not open metadata file at: " + path);
  }

  return Metadata::from(in);
}

} // namespace metadata
} // namespace parcore
