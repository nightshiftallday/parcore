#include <boost/program_options.hpp>
#include <boost/program_options/value_semantic.hpp>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

#include <arrow/array.h>
#include <coyote/cDefs.hpp>
#include <coyote/cThread.hpp>
#include <libstf/buffer.hpp>
#include <libstf/common.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/tlb_manager.hpp>
#include <parcore/cpu/cpu.hpp>
#include <parcore/metadata/utils.hpp>
#include <parcore/reader.hpp>
#include <unistd.h>

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this
// is the only possible value
#define DEFAULT_VFPGA_ID 0
#define N_REPS 64

const std::string separator = std::string(80, '-');

void time(std::string file_path, parcore::Reader &reader,
          std::shared_ptr<arrow::io::RandomAccessFile> file, size_t i, size_t j,
          size_t values, size_t reps, bool print) {
  std::chrono::high_resolution_clock::rep fpga_us = 0, cpu_us = 0;

  for (size_t k = 0; k < reps; ++k) {
    auto start = std::chrono::high_resolution_clock::now();
    reader.enqueue_column_chunk(i, j);
    auto fpga_data = reader.next_column_chunk();
    auto end = std::chrono::high_resolution_clock::now();
    fpga_us +=
        std::chrono::duration_cast<std::chrono::microseconds>(end - start)
            .count();

    start = std::chrono::high_resolution_clock::now();
    auto cpu_data_raw = parcore::cpu::read_column_chunk(file, i, j);
    end = std::chrono::high_resolution_clock::now();
    cpu_us += std::chrono::duration_cast<std::chrono::microseconds>(end - start)
                  .count();
    usleep(10000); // sleep 10ms
  }

  fpga_us /= reps;
  cpu_us /= reps;

  if (print)
    std::cout << file_path << "," << i << "," << j << "," << values << ","
              << fpga_us << "," << cpu_us << std::endl;
}

void benchmark(std::string parquet_file, size_t discard_reps, size_t reps) {
  auto meta = parcore::metadata::from_file(parquet_file + ".meta");
  auto cthread = std::make_shared<coyote::cThread>(DEFAULT_VFPGA_ID, getpid());
#ifdef ENABLE_SIMULATION
  auto pool = std::make_shared<libstf::SimpleMemoryPool>();
#else
  auto pool = std::make_shared<libstf::HugePageMemoryPool>();
#endif
  auto tlb = std::make_shared<libstf::TLBManager>(cthread, pool);
#ifdef ENABLE_SIMULATION
  tlb->ensure_tlb_mapping(pool->initial_address(), pool->total_capacity());
#endif

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

  libstf::GlobalConfig global_config(cthread);
  if (!global_config.has_config(parcore::PageDecoderConfig::ID)) {
    throw std::runtime_error("flashed design doesn't have PageDecoderConfig");
  }
  auto addr_offset = std::get<0>(
      global_config.get_config_bounds(parcore::PageDecoderConfig::ID));
  parcore::PageDecoderConfig decoder_config(cthread, addr_offset);

  parcore::Reader reader(cthread, pool, tlb, decoder_config, meta, data);

  for (size_t i = 0; i < meta.groups.size(); ++i) {
    auto group = meta.groups[i];
    for (size_t j = 0; j < group.chunks.size(); ++j) {
      auto values = group.chunks[j].num_values;
      time(parquet_file, reader, file, i, j, values, discard_reps, false);
      time(parquet_file, reader, file, i, j, values, reps, true);
    }
  }
}

int main(int argc, char *argv[]) {
  std::vector<std::string> files;
  size_t discard_reps, reps;

  boost::program_options::options_description runtime_options(
      "Parcore benchmark");
  runtime_options.add_options()(
      "file,f", boost::program_options::value(&files)->multitoken(),
      "Path to the parquet files to benchmark on")(
      "discard_reps,d",
      boost::program_options::value<size_t>(&discard_reps)->default_value(5),
      "The number of times to decode each page for benchmarking (will be "
      "discarded, not accounted for in the results)")(
      "reps,r",
      boost::program_options::value<size_t>(&reps)->default_value(N_REPS),
      "The number of times to decode each page for benchmarking");
  boost::program_options::variables_map command_line_arguments;
  boost::program_options::store(
      boost::program_options::parse_command_line(argc, argv, runtime_options),
      command_line_arguments);
  boost::program_options::notify(command_line_arguments);

  std::cout << "file,group,column,values,fpga,cpu" << std::endl;
  for (auto file : files) {
    benchmark(file, discard_reps, reps);
  }

  return EXIT_SUCCESS;
}
