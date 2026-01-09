#include <boost/program_options.hpp>
#include <boost/program_options/value_semantic.hpp>
#include <chrono>
#include <coyote/cDefs.hpp>
#include <coyote/cThread.hpp>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <arrow/array.h>
#include <libstf/buffer.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/tlb_manager.hpp>
#include <optional>
#include <parcore/cpu/cpu.hpp>
#include <parcore/fpga.hpp>
#include <parcore/metadata/utils.hpp>
#include <parcore/profiling.hpp>
#include <parcore/reader.hpp>
#include <stdexcept>
#include <string>

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this
// is the only possible value
#define DEFAULT_VFPGA_ID 0

const std::string separator = std::string(80, '-');

void diff(const void *d1, const void *d2, size_t size) {
  auto d1b = reinterpret_cast<const uint8_t *>(d1);
  auto d2b = reinterpret_cast<const uint8_t *>(d2);
  for (size_t i = 0; i < size; ++i) {
    if (d1b[i] != d2b[i]) {
      throw std::runtime_error("output mismatch at byte " + std::to_string(i) +
                               ", expected " + std::to_string(d1b[i]) +
                               " but instead got " + std::to_string(d2b[i]));
    }
  }

  std::cout << size << " bytes match" << std::endl;
}

int main(int argc, char *argv[]) {
  parcore::profiler::init();

  std::string parquet_file;
  size_t start, end;

  boost::program_options::options_description runtime_options(
      "Parcore example");
  runtime_options.add_options()(
      "file,f", boost::program_options::value<std::string>(&parquet_file),
      "Path to the parquet file to parse")(
      "start,s",
      boost::program_options::value<size_t>(&start)->default_value(0),
      "The first page to process")(
      "end,e", boost::program_options::value<size_t>(&end)->default_value(0),
      "The last page to process. 0 means to process all");
  boost::program_options::variables_map command_line_arguments;
  boost::program_options::store(
      boost::program_options::parse_command_line(argc, argv, runtime_options),
      command_line_arguments);
  boost::program_options::notify(command_line_arguments);

  parcore::profiler::start();

  auto meta = parcore::metadata::from_file(parquet_file + ".meta");
  if (start > meta.groups.size() || start > end || end > meta.groups.size())
    throw std::runtime_error("invalid start/end bounds");

  if (end <= 0)
    end = meta.groups.size();

  auto cthread = std::make_shared<coyote::cThread>(DEFAULT_VFPGA_ID, getpid());
  auto pool = std::make_shared<libstf::HugePageMemoryPool>();
  auto tlb = std::make_shared<libstf::TLBManager>(*cthread, *pool);
  tlb->ensure_tlb_mapping(pool->initial_address(), pool->total_capacity());
  std::cout << "mapped at " << std::hex << pool->initial_address()
            << " with size " << std::dec << pool->total_capacity() << std::endl;

  std::ifstream in(parquet_file, std::ios::binary);
  if (!in) {
    throw std::runtime_error("could not open file at: " + parquet_file);
  }
  auto data_vector = std::vector<uint8_t>(std::istreambuf_iterator<char>(in),
                                          std::istreambuf_iterator<char>());

  void *data_ptr;
  auto status = pool->allocate(data_vector.size(), &data_ptr);
  if (!status.ok()) {
    throw std::runtime_error(
        "could not allocate memory for parquet file data: " + status.message());
  }
  auto data = libstf::make_buffer(pool, data_ptr, data_vector.size(),
                                  data_vector.size());
  std::memcpy(data->ptr, data_vector.data(), data_vector.size());

  auto file =
      std::make_shared<parcore::cpu::InMemoryRandomAccessFile>(data_vector);
  parcore::Reader reader(cthread, pool, tlb, meta, data);

  for (size_t i = start; i < end; ++i) {
    auto group = meta.groups[i];
    for (size_t j = 0; j < group.chunks.size(); ++j) {
      auto chunk = group.chunks[j];

      std::cout << separator << std::endl;
      std::cout << "Decoding column chunk " << i << ":" << j << ":"
                << std::endl;
      std::cout << "\tcompression: " << chunk.compression << std::endl;
      std::cout << "\ttype: " << chunk.type << std::endl;
      std::cout << "\tdictionary: " << (chunk.dictionary != std::nullopt)
                << std::endl;

      auto start = std::chrono::high_resolution_clock::now();

      reader.enqueue_column_chunk(i, j);
      auto fpga_data = reader.next_column_chunk();

      auto end = std::chrono::high_resolution_clock::now();
      auto fpga_us =
          std::chrono::duration_cast<std::chrono::microseconds>(end - start)
              .count();

      start = std::chrono::high_resolution_clock::now();

      auto cpu_data_raw = parcore::cpu::read_column_chunk(file, i, j);

      end = std::chrono::high_resolution_clock::now();
      auto cpu_us =
          std::chrono::duration_cast<std::chrono::microseconds>(end - start)
              .count();
      std::cout << "\tcompleted! FPGA took " << fpga_us << "us, CPU took "
                << cpu_us << "us" << std::endl;

      std::vector<uint8_t> cpu_data;
      for (const auto &cc : cpu_data_raw->chunks()) {
        auto arr = std::static_pointer_cast<arrow::PrimitiveArray>(cc);
        const uint8_t *data = arr->data()->GetValues<uint8_t>(1);
        size_t byte_size = arr->length() * parcore::type_data_size(chunk.type);
        cpu_data.insert(cpu_data.end(), data, data + byte_size);
      }

      diff(cpu_data.data(), fpga_data->ptr, fpga_data->size);
    }
  }

  parcore::profiler::flush();
  return EXIT_SUCCESS;
}
