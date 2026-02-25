#include <boost/type.hpp>
#include <memory>
#include <optional>
#include <queue>
#include <vector>

#include <parcore/base_reader.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/multi_reader.hpp>

namespace parcore {

constexpr const double TRANSFER_FACTOR = 1.0;
constexpr const double DECOMPRESS_FACTOR = 1.0;
constexpr const double PLAIN_FACTOR = 1.0;
constexpr const double HYBRID_FACTOR = 1.0;

MultiReader::MultiReader(std::vector<std::shared_ptr<Reader>> readers)
    : readers_(readers), transfer_factor_(TRANSFER_FACTOR),
      decompress_factor_(DECOMPRESS_FACTOR), plain_factor_(PLAIN_FACTOR),
      hybrid_factor_(HYBRID_FACTOR) {
  for (size_t i = 0; i < readers_.size(); ++i) {
    decoder_heap_.push({i, 0.0});
  }
}

const metadata::Metadata &MultiReader::metadata() const {
  assert(readers_.size() > 0);
  return readers_[0]->metadata();
}

void MultiReader::enqueue_column_chunk(size_t chunk, size_t column) {
  auto column_chunk = get_column_chunk(metadata(), chunk, column);
  double cost = compute_cost(column_chunk);

  auto state = decoder_heap_.top();
  decoder_heap_.pop();

  size_t decoder_id = state.id;

  readers_[decoder_id]->enqueue_column_chunk(chunk, column);

  // Record scheduling order
  scheduled_order_.push_back(decoder_id);

  state.available_time += cost;
  decoder_heap_.push(state);
}

bool MultiReader::has_next_column_chunk() {
  if (scheduled_order_.empty())
    return false;

  size_t decoder_id = scheduled_order_.front();
  return readers_[decoder_id]->has_next_column_chunk();
}

std::vector<std::shared_ptr<libstf::Buffer>> MultiReader::next_column_chunk() {
  if (scheduled_order_.empty())
    return {};

  size_t decoder_id = scheduled_order_.front();

  auto result = readers_[decoder_id]->next_column_chunk();

  scheduled_order_.pop_front();

  return result;
}

inline size_t get_input_bytes(const metadata::ColumnChunk &column_chunk) {
  size_t bytes = 0;

  if (column_chunk.dictionary != std::nullopt)
    bytes += column_chunk.dictionary->size;

  for (auto page : column_chunk.data)
    bytes += page.size;

  return bytes;
}

inline size_t get_output_bytes(const metadata::ColumnChunk &column_chunk) {
  return column_chunk.num_values * libstf::size_of(column_chunk.type);
}

double
MultiReader::compute_cost(const metadata::ColumnChunk &column_chunk) const {
  const auto &chunk_meta = column_chunk;

  size_t input_bytes = get_input_bytes(column_chunk);
  size_t output_bytes = get_output_bytes(column_chunk);

  double T_input = transfer_factor_ * input_bytes;

  double T_output = transfer_factor_ * output_bytes;

  double T_decompress = 0.0;
  if (chunk_meta.compression != metadata::Compression::RAW) {
    T_decompress = decompress_factor_ * input_bytes;
  }

  double T_decode = 0.0;
  for (const auto &page : chunk_meta.data) {
    double encoding_factor = (page.encoding == metadata::Encoding::HYBRID)
                                 ? hybrid_factor_
                                 : plain_factor_;

    T_decode += page.num_values * encoding_factor;
  }

  return T_input + T_output + T_decompress + T_decode;
}

} // namespace parcore
