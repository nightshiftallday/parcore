#pragma once

#include <memory>

#include <libstf/buffer.hpp>
#include <parcore/metadata/metadata.hpp>

namespace parcore {

class Reader {
public:
  [[nodiscard]] virtual const metadata::Metadata &metadata() const = 0;

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   */
  virtual void enqueue_column_chunk(size_t chunk, size_t column) = 0;

  /**
   * Returns whether there is a column chunk enqueued for processing. If this
   * function returns true, then the consumer can call `next_column_chunk` to
   * retrieve the output data, potentially blocking on until the acceleartor
   * is done processing.
   */
  [[nodiscard]] virtual bool has_next_column_chunk() = 0;

  /**
   * Retrieves the next column chunk that has been enqueued for processing.
   */
  [[nodiscard]] virtual std::vector<std::shared_ptr<libstf::Buffer>>
  next_column_chunk() = 0;
};

} // namespace parcore
