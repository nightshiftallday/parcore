#include <boost/program_options.hpp>
#include <boost/program_options/value_semantic.hpp>
#include <chrono>
#include <coyote/cDefs.hpp>
#include <coyote/cThread.hpp>
#include <cstdint>
#include <cstdlib>
#include <cstring>

#include <optional>
#include <parcore/cpu/cpu.hpp>
#include <parcore/fpga.hpp>
#include <parcore/metadata/utils.hpp>
#include <parcore/utils.hpp>

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this
// is the only possible value
#define DEFAULT_VFPGA_ID 0
#define N_REPS 64

const std::string separator = std::string(80, '-');

inline std::chrono::high_resolution_clock::rep
benchmark_page_cpu(std::shared_ptr<arrow::io::RandomAccessFile> file,
                   size_t chunk, size_t column) {
  auto start = std::chrono::high_resolution_clock::now();
  parcore::cpu::read_column_chunk(file, chunk, column);
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::high_resolution_clock::now() - start)
      .count();
}

inline std::chrono::high_resolution_clock::rep benchmark_page_fpga(
    std::shared_ptr<coyote::cThread> cthread, arrow::MemoryPool *pool,
    const parcore::metadata::Metadata &meta, const std::vector<uint8_t> data,
    size_t chunk, size_t column) {
  auto start = std::chrono::high_resolution_clock::now();
  parcore::utils::read_column_chunk(cthread, pool, meta, data, chunk, column);
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::high_resolution_clock::now() - start)
      .count();
}

int main(int argc, char *argv[]) {
  std::string parquet_file;
  size_t start, end, reps;

  boost::program_options::options_description runtime_options(
      "Parcore example");
  runtime_options.add_options()(
      "file,f", boost::program_options::value<std::string>(&parquet_file),
      "Path to the parquet file to parse")(
      "start,s",
      boost::program_options::value<size_t>(&start)->default_value(0),
      "The first page to process")(
      "end,e", boost::program_options::value<size_t>(&end)->default_value(0),
      "The last page to process. 0 means to process all")(
      "reps,r",
      boost::program_options::value<size_t>(&reps)->default_value(N_REPS),
      "The number of times to decode each page for benchmarking");
  boost::program_options::variables_map command_line_arguments;
  boost::program_options::store(
      boost::program_options::parse_command_line(argc, argv, runtime_options),
      command_line_arguments);
  boost::program_options::notify(command_line_arguments);

  std::ifstream in(parquet_file, std::ios::binary);
  if (!in) {
    throw std::runtime_error("could not open file at: " + parquet_file);
  }
  auto data = std::vector<uint8_t>(std::istreambuf_iterator<char>(in),
                                   std::istreambuf_iterator<char>());
  auto meta = parcore::metadata::from_file(parquet_file + ".meta");
  auto file = std::make_shared<parcore::cpu::InMemoryRandomAccessFile>(data);

  auto cthread = std::make_shared<coyote::cThread>(DEFAULT_VFPGA_ID, getpid());
  cthread->userMap(data.data(), data.size());

  if (start > meta.groups.size() || start > end || end > meta.groups.size())
    throw std::runtime_error("invalid start/end bounds");
  if (end <= 0)
    end = meta.groups.size();

  auto pool = arrow::default_memory_pool();
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

      // CPU runs
      std::chrono::high_resolution_clock::rep total_time = 0;
      for (auto k = 0; k < reps; ++k) {
        total_time += benchmark_page_cpu(file, i, j);
      }
      auto cpu_time = total_time / reps;

      // FPGA runs
      total_time = 0;
      for (auto k = 0; k < reps; ++k) {
        total_time += benchmark_page_fpga(cthread, pool, meta, data, i, j);
      }
      auto fpga_time = total_time / reps;

      std::cout << "cpu time:  " << cpu_time << " ns" << std::endl;
      std::cout << "fpga time: " << fpga_time << " ns" << std::endl;
    }
  }

  return EXIT_SUCCESS;
}
