#include <boost/type.hpp>
#include <condition_variable>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <queue>
#include <vector>

#include <parcore/fpga/adaptor.hpp>
#include <parcore/metadata/metadata.hpp>
#include <parcore/multi_reader.hpp>
#include <parcore/reader.hpp>

namespace parcore {

MultiReader::MultiReader(
    std::vector<std::shared_ptr<fpga::HardwareReader>> readers)
    : readers_(std::move(readers)) {
  for (size_t i = 0; i < readers_.size(); ++i) {
    idle_readers_.push(i);
  }
}

const metadata::Metadata &MultiReader::metadata() const {
  return readers_[0]->metadata();
}

void MultiReader::enqueue_column_chunk(size_t chunk, size_t column) {
  auto column_chunk = get_column_chunk(this->metadata(), chunk, column);

  std::unique_lock<std::mutex> lock(queue_mtx_);

  QueuedTask task{chunk, column, next_seq_to_enqueue_++,
                  column_chunk.num_values, column_chunk.type};

  if (!idle_readers_.empty()) {
    size_t reader_idx = idle_readers_.front();
    idle_readers_.pop();
    dispatch_task_to_reader(task, reader_idx);
  } else {
    task_queue_.push(task);
  }
}

std::optional<MultiReader::QueuedTask>
MultiReader::assign_next_column_chunk_to_reader(libstf::stream_t reader_id) {
  std::lock_guard<std::mutex> lock(queue_mtx_);

  if (!task_queue_.empty()) {
    auto task = task_queue_.front();
    task_queue_.pop();
    return task;
  } else {
    idle_readers_.push(reader_id);
    return std::nullopt;
  }
}

// Internal helper (called with lock held)
void MultiReader::dispatch_task_to_reader(QueuedTask task,
                                          libstf::stream_t reader_id) {
  auto handle =
      readers_[reader_id]->decode_column_chunk(task.chunk, task.column);

  // Release lock before hardware call if decode_column_chunk is slow to
  // initiate but here we keep it simple.
  handle->add_callback(
      [this, reader_id, handle, task](libstf::stream_t stream) {
        auto result = fpga::collect_from_output_handle_into_arrow(
            handle, stream, task.num_values, task.type);

        {
          std::lock_guard<std::mutex> lock(reorder_buffer_mtx_);
          reorder_buffer_[task.sequence_id] = std::move(result);
          cv_finished_.notify_all();
        }

        auto task = assign_next_column_chunk_to_reader(reader_id);
        if (task != std::nullopt) {
          dispatch_task_to_reader(*task, reader_id);
        }
      });
}

bool MultiReader::has_next_column_chunk() {
  std::lock_guard<std::mutex> lock(queue_mtx_);
  return next_seq_to_return_ < next_seq_to_enqueue_;
}

std::shared_ptr<arrow::ChunkedArray> MultiReader::next_column_chunk() {
  std::shared_ptr<arrow::ChunkedArray> result;
  {
    std::unique_lock<std::mutex> lock(reorder_buffer_mtx_);

    if (!reorder_buffer_.contains(next_seq_to_return_)) {
      cv_finished_.wait(lock, [this] {
        return reorder_buffer_.contains(next_seq_to_return_);
      });
    }

    auto it = reorder_buffer_.find(next_seq_to_return_++);
    result = std::move(it->second);
    reorder_buffer_.erase(it);
  } // lock is released here

  return result; // Return occurs outside the mutex
}

} // namespace parcore
