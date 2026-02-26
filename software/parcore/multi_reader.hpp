#pragma once

#include <deque>
#include <queue>

#include <parcore/metadata/metadata.hpp>
#include <parcore/reader.hpp>

namespace parcore {

class MultiReader : public Reader {
private:
  struct DecoderState {
    size_t id;
    double available_time;

    bool operator>(const DecoderState &other) const {
      return available_time > other.available_time;
    }
  };

public:
  MultiReader(std::vector<std::shared_ptr<Reader>> readers);

  [[nodiscard]] const metadata::Metadata &metadata() const override;

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] bool has_next_column_chunk() override;

  [[nodiscard]] std::shared_ptr<arrow::ChunkedArray>
  next_column_chunk() override;

private:
  double compute_cost(const metadata::ColumnChunk &column_chunk) const;

  std::vector<std::shared_ptr<Reader>> readers_;
  std::priority_queue<DecoderState, std::vector<DecoderState>,
                      std::greater<DecoderState>>
      decoder_heap_;
  // The order of decoders used, so that we can fetch data from them in the
  // appropriate order.
  std::deque<size_t> scheduled_order_;

  // Coefficients for computing the next decoder to use
  double transfer_factor_;
  double decompress_factor_;
  double plain_factor_;
  double hybrid_factor_;
};

template <typename T, typename... Args>
std::shared_ptr<MultiReader> make_multi_reader(size_t count, Args &&...args) {
  static_assert(std::is_base_of_v<Reader, T>, "T must derive from Reader");

  std::vector<std::shared_ptr<Reader>> readers;
  readers.reserve(count);

  for (size_t i = 0; i < count; ++i) {
    readers.push_back(
        std::make_shared<T>(std::forward<Args>(args)...,
                            static_cast<libstf::stream_t>(i) // decoder = i
                            ));
  }

  return std::make_shared<MultiReader>(std::move(readers));
}

} // namespace parcore
