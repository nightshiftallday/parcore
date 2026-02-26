#include <parquet/arrow/reader.h>

#include <parcore/base_reader.hpp>
#include <parcore/hybrid_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <stdexcept>

namespace parcore {

HybridReader::HybridReader(std::shared_ptr<Reader> hardware_reader,
                           std::shared_ptr<Reader> software_reader)
    : hardware_reader_(std::move(hardware_reader)),
      software_reader_(std::move(software_reader)) {}

void HybridReader::enqueue_column_chunk(size_t chunk, size_t column) {
  auto column_chunk = get_column_chunk(metadata(), chunk, column);

  if (metadata::is_libstf_type(column_chunk.type)) {
    chosen_decoder_.push(Decoder::HARDWARE);
    hardware_reader_->enqueue_column_chunk(chunk, column);
  } else {
    chosen_decoder_.push(Decoder::SOFTWARE);
    software_reader_->enqueue_column_chunk(chunk, column);
  }
}

bool HybridReader::has_next_column_chunk() {
  if (chosen_decoder_.empty())
    return false;

  switch (chosen_decoder_.front()) {
  case Decoder::HARDWARE:
    return hardware_reader_->has_next_column_chunk();
  case Decoder::SOFTWARE:
    return software_reader_->has_next_column_chunk();
  default:
    throw std::runtime_error("unexpected Decoder");
  }
}

std::vector<std::shared_ptr<libstf::Buffer>> HybridReader::next_column_chunk() {
  assert(!chosen_decoder_.empty());

  auto decoder = chosen_decoder_.front();
  chosen_decoder_.pop();

  switch (decoder) {
  case Decoder::HARDWARE:
    return hardware_reader_->next_column_chunk();
  case Decoder::SOFTWARE:
    return software_reader_->next_column_chunk();
  default:
    throw std::runtime_error("unexpected Decoder");
  }
}

} // namespace parcore
