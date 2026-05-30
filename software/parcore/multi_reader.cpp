#include <boost/type.hpp>
#include <memory>
#include <vector>

#include <parcore/metadata/metadata.hpp>
#include <parcore/multi_reader.hpp>
#include <parcore/reader.hpp>

namespace parcore {

constexpr const double TRANSFER_FACTOR = 6.448357e-05;
constexpr const double DECOMPRESS_FACTOR = 1.086285e+01;
constexpr const double PLAIN_FACTOR = 6.081019e-04;
constexpr const double HYBRID_FACTOR = 4.319163e-05;
constexpr const double SETUP_FACTOR = 7.829579e+00;

MultiReader::MultiReader(std::vector<std::shared_ptr<Reader>> readers)
    : readers_(readers) {
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

std::shared_ptr<arrow::ChunkedArray> MultiReader::next_column_chunk() {
  if (scheduled_order_.empty())
    return {};

  size_t decoder_id = scheduled_order_.front();

  auto result = readers_[decoder_id]->next_column_chunk();

  scheduled_order_.pop_front();

  return result;
}

inline size_t get_input_bytes(const metadata::ColumnChunk &column_chunk) {
  return column_chunk.total_compressed_size;
}

inline size_t get_output_bytes(const metadata::ColumnChunk &column_chunk) {
  auto type = metadata::to_libstf_type(column_chunk.type);
  return column_chunk.num_values * libstf::size_of(type);
}

double
MultiReader::compute_cost(const metadata::ColumnChunk &column_chunk) const {
  size_t input_bytes = get_input_bytes(column_chunk);
  size_t output_bytes = get_output_bytes(column_chunk);

  double T_config = SETUP_FACTOR;

  double T_input = TRANSFER_FACTOR * input_bytes;
  double T_output = TRANSFER_FACTOR * output_bytes;

  double T_decompress = 0.0;
  if (column_chunk.compression != metadata::Compression::RAW)
    T_decompress = DECOMPRESS_FACTOR * input_bytes;

  double T_decode = PLAIN_FACTOR * column_chunk.num_values;

  return T_config + T_input + T_output + T_decompress + T_decode;
}

} // namespace parcore
