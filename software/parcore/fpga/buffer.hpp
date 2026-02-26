#pragma once

#include <arrow/buffer.h>
#include <libstf/buffer.hpp>

namespace parcore {

namespace fpga {

class Buffer : public arrow::Buffer {
public:
  /**
   * Creates a new instance of an Arrow Buffer referencing some libstf::Buffer
   * memory.
   *
   * @param buf A shared pointer to the libstf::Buffer.
   */
  Buffer(std::shared_ptr<libstf::Buffer> buf);

private:
  std::shared_ptr<libstf::Buffer> buf_;
};

} // namespace fpga

} // namespace parcore
