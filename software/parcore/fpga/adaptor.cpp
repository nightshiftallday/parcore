#include <parcore/fpga/adaptor.hpp>
#include <parcore/fpga/buffer.hpp>

namespace parcore {

namespace fpga {

std::shared_ptr<arrow::ChunkedArray> collect_from_output_handle_into_arrow(
    std::shared_ptr<libstf::OutputHandle> output_handle,
    libstf::stream_t decoder, size_t num_values, metadata::Type type) {
  std::vector<std::shared_ptr<arrow::Array>> chunks;
  while (output_handle->stream_has_more_output(decoder)) {
    auto buf = output_handle->get_next_stream_output(decoder);
    auto wrapper = std::make_shared<Buffer>(std::move(buf));

    auto arrow_type = metadata::to_arrow_type(type);

    auto array_data =
        arrow::ArrayData::Make(arrow_type, num_values, {nullptr, wrapper});
    auto array = arrow::MakeArray(array_data);
    chunks.push_back(array);
  }

  return std::make_shared<arrow::ChunkedArray>(std::move(chunks));
}

} // namespace fpga

} // namespace parcore
