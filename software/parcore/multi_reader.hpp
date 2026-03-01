#pragma once

#include <map>

#include <parcore/fpga/reader.hpp>
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
  MultiReader(std::vector<std::shared_ptr<fpga::HardwareReader>> readers);

  [[nodiscard]] const metadata::Metadata &metadata() const override;

  void enqueue_column_chunk(size_t chunk, size_t column) override;

  [[nodiscard]] bool has_next_column_chunk() override;

  [[nodiscard]] std::shared_ptr<arrow::ChunkedArray>
  next_column_chunk() override;

private:
  std::vector<std::shared_ptr<fpga::HardwareReader>> readers_;

  struct QueuedTask {
    size_t chunk;
    size_t column;
    size_t sequence_id;
    size_t num_values;
    metadata::Type type;
  };

  std::queue<QueuedTask> task_queue_;
  std::queue<size_t> idle_readers_;
  size_t next_seq_to_enqueue_ = 0;
  size_t next_seq_to_return_ = 0;
  std::mutex queue_mtx_;

  std::map<libstf::stream_t, std::shared_ptr<arrow::ChunkedArray>>
      reorder_buffer_;
  std::mutex reorder_buffer_mtx_;

  std::condition_variable cv_finished_;

  std::optional<QueuedTask>
  assign_next_column_chunk_to_reader(libstf::stream_t reader_id);
  void dispatch_task_to_reader(QueuedTask task, libstf::stream_t reader_id);
};

template <typename T, typename... Args>
std::shared_ptr<MultiReader> make_multi_reader(size_t count, Args &&...args) {
  static_assert(std::is_base_of_v<fpga::HardwareReader, T>,
                "T must derive from HardwareReader");

  std::vector<std::shared_ptr<fpga::HardwareReader>> readers;
  readers.reserve(count);

  for (size_t i = 0; i < count; ++i) {
    readers.push_back(
        std::make_shared<T>(args..., static_cast<libstf::stream_t>(i)));
  }

  return std::make_shared<MultiReader>(std::move(readers));
}

} // namespace parcore
