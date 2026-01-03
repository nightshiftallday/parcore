#pragma once

#include <arrow/io/file.h>
#include <vector>

namespace parcore {
namespace cpu {

// Originally from https://stackoverflow.com/questions/72240424

class InMemoryRandomAccessFile : public arrow::io::RandomAccessFile {
public:
  InMemoryRandomAccessFile(const std::vector<char> &data);
  arrow::Result<int64_t> ReadAt(int64_t position, int64_t nbytes,
                                void *out) override;
  arrow::Result<std::shared_ptr<arrow::Buffer>> ReadAt(int64_t position,
                                                       int64_t nbytes) override;
  arrow::Result<int64_t> Read(int64_t nbytes, void *out) override;
  arrow::Result<std::shared_ptr<arrow::Buffer>> Read(int64_t nbytes) override;
  arrow::Result<int64_t> GetSize() override;
  arrow::Result<int64_t> Tell() const override;
  arrow::Status Seek(int64_t position) override;
  arrow::Status Close() override;
  bool closed() const override;

private:
  bool is_closed;
  const std::vector<char> &data_;
  uint64_t position_;
};

std::shared_ptr<arrow::ChunkedArray>
read_column_chunk(const arrow::io::RandomAccessFile &file, size_t chunk,
                  size_t column);

} // namespace cpu
} // namespace parcore
