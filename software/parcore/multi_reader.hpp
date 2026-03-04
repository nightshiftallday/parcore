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
};

} // namespace parcore
