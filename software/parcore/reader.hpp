#pragma once

#include <arrow/chunked_array.h>
#include <parcore/metadata/metadata.hpp>

namespace parcore {

class Reader {
public:
  [[nodiscard]] virtual const metadata::Metadata &metadata() const = 0;

  /**
   * Submits a column chunk for parsing, which includes decompression, decoding
   * and potentially dictionary mapping.
   *
   * @param chunk      The index of the chunk to decode
   * @param column     The index of the column to decode
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
  [[nodiscard]] virtual std::shared_ptr<arrow::ChunkedArray>
  next_column_chunk() = 0;
};

const metadata::ColumnChunk get_column_chunk(const metadata::Metadata &meta,
                                             size_t chunk, size_t column);

} // namespace parcore
