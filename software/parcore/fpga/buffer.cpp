#include <parcore/fpga/buffer.hpp>

namespace parcore {

namespace fpga {

Buffer::Buffer(std::shared_ptr<libstf::Buffer> buf)
    : arrow::Buffer(static_cast<uint8_t *>(buf->ptr), buf->size), buf_(buf) {}

} // namespace fpga

} // namespace parcore
