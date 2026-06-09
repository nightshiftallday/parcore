#include <parcore/adaptor.hpp>

namespace parcore {

static std::shared_ptr<arrow::DataType> to_arrow_type(metadata::Type typ) {
  switch (typ) {
  case metadata::Type::BYTE_T:
    return arrow::boolean();
  case metadata::Type::INT32_T:
    return arrow::int32();
  case metadata::Type::INT64_T:
    return arrow::int64();
  case metadata::Type::FLOAT_T:
    return arrow::float32();
  case metadata::Type::DOUBLE_T:
    return arrow::float64();
  default:
    throw std::runtime_error("cannot convert type to arrow::DataType");
  }
}

Buffer::Buffer(std::shared_ptr<libstf::Buffer> buf)
    : arrow::Buffer(static_cast<uint8_t *>(buf->ptr), buf->size), buf_(buf) {}

std::shared_ptr<arrow::ChunkedArray>
libstf_buffers_into_arrow(std::vector<std::shared_ptr<libstf::Buffer>> buffers,
                          size_t num_values, metadata::Type type) {
  std::vector<std::shared_ptr<arrow::Array>> chunks;
  for (auto buf : buffers) {
    auto wrapper = std::make_shared<Buffer>(std::move(buf));

    auto arrow_type = to_arrow_type(type);

    auto array_data =
        arrow::ArrayData::Make(arrow_type, num_values, {nullptr, wrapper});
    auto array = arrow::MakeArray(array_data);
    chunks.push_back(array);
  }

  return std::make_shared<arrow::ChunkedArray>(std::move(chunks));
}

} // namespace parcore
