#include <parcore/multi_reader.hpp>

namespace parcore {

MultiReader::MultiReader(std::vector<std::shared_ptr<Reader>> readers)
    : readers_(readers) {}

const metadata::Metadata &MultiReader::metadata() const {
  assert(readers_.size() > 0);
  return readers_[0]->metadata();
}

void MultiReader::enqueue_column_chunk(size_t chunk, size_t column) {
  auto &reader = readers_[enqueue_index_];
  reader->enqueue_column_chunk(chunk, column);
  enqueue_index_ = (enqueue_index_ + 1) % readers_.size();
}

bool MultiReader::has_next_column_chunk() {
  for (size_t i = 0; i < readers_.size(); ++i) {
    size_t idx = (next_index_ + i) % readers_.size();
    if (readers_[idx]->has_next_column_chunk()) {
      next_index_ = idx;
      return true;
    }
  }

  return false;
}

std::vector<std::shared_ptr<libstf::Buffer>> MultiReader::next_column_chunk() {
  auto &reader = readers_[next_index_];
  auto result = reader->next_column_chunk();
  next_index_ = (next_index_ + 1) % readers_.size();
  return result;
}

} // namespace parcore
