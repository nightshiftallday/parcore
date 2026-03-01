#include <boost/program_options.hpp>
#include <boost/program_options/value_semantic.hpp>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <optional>
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
#include <parcore/cpu/cpu_reader.hpp>
#include <parcore/fpga/preload_file_reader.hpp>
#include <parcore/metadata/utils.hpp>
#include <unistd.h>

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this
// is the only possible value
#define DEFAULT_VFPGA_ID 0
#define N_REPS 10

const std::string separator = std::string(80, '-');

void time(std::string path,
          std::shared_ptr<parcore::fpga::PreloadFileReader> hardware_reader,
          std::shared_ptr<parcore::cpu::CPUReader> software_reader, size_t i,
          size_t j, size_t values, size_t reps, bool print) {
  std::chrono::high_resolution_clock::rep fpga_us = 0, cpu_us = 0;
}

std::shared_ptr<libstf::OutputBufferManager> obm;

static void handle_fpga_interrupt(int value) {
  // The nullptr is a bit ugly but this function is private any can only be
  // called from the cthread, which means the private constructor was executed
  // and the context has been initialized!
  //
  // Note that we needed to implement the "handle_fpga_interrupt" function as a
  // static function due to a limitation in Coyote. The reason is that we need
  // to register a function pointer with Coyote to call when an interrupt is
  // triggered on the FPGA. However, Coyote only accepts a raw function pointer.
  // Raw function points can only be created in C++ from static methods. See
  // https://isocpp.org/wiki/faq/pointers-to-members#fnptr-vs-memfnptr-types In
  // particular, they cannot be created from what's called a
  // pointer-to-member-function: > NOTE: do not attempt to “cast” a poi
  // ter-to-member-function into a pointer-to-function; > the result is
  // undefined and probably disastrous.
  //   (From above link)
  obm->handle_fpga_interrupt(value);
}

int main(int argc, char *argv[]) {
  std::string path;
  size_t discard_reps, reps;
  uint32_t num_decoders;

  boost::program_options::options_description runtime_options(
      "Parcore benchmark");
  runtime_options.add_options()("file,f", boost::program_options::value(&path),
                                "Path to the parquet files to benchmark on")(
      "reps,r",
      boost::program_options::value<size_t>(&reps)->default_value(N_REPS),
      "The number of times to decode each page for benchmarking");
  boost::program_options::variables_map command_line_arguments;
  boost::program_options::store(
      boost::program_options::parse_command_line(argc, argv, runtime_options),
      command_line_arguments);
  boost::program_options::notify(command_line_arguments);

  std::cout
      << "file,i,j,compressed,num_pages,input_bytes_plain,input_bytes_hybrid,"
         "output_bytes_plain,output_bytes_hybrid,num_values_plain,num_values_"
         "hybrid,time"
      << std::endl;

  auto meta = parcore::metadata::from_file(path + ".meta");
  auto cthread = std::make_shared<coyote::cThread>(DEFAULT_VFPGA_ID, getpid(),
                                                   0, &handle_fpga_interrupt);
#ifdef ENABLE_SIMULATION
  auto pool = std::make_shared<libstf::SimpleMemoryPool>();
#else
  auto pool = std::make_shared<libstf::HugePageMemoryPool>();
#endif
  auto tlb = std::make_shared<libstf::TLBManager>(cthread, pool);
#ifdef ENABLE_SIMULATION
  tlb->ensure_tlb_mapping(pool->initial_address(), pool->total_capacity());
#endif

  auto maybe_file =
      arrow::io::MemoryMappedFile::Open(path, arrow::io::FileMode::READ);
  if (!maybe_file.ok())
    throw std::runtime_error("could not open parquet file: " +
                             maybe_file.status().message());
  auto file = maybe_file.ValueOrDie();

  libstf::GlobalConfig global_config(cthread);
  auto mem_config = global_config.get_config<libstf::MemConfig>();
  auto column_chunk_config =
      global_config.get_config<parcore::ColumnChunkDecoderConfig>();
  auto page_config = global_config.get_config<parcore::PageDecoderConfig>();

#ifdef ENABLE_SIMULATION
  obm = std::make_shared<libstf::OutputBufferManager>(
      cthread, mem_config, pool, tlb, 2, 1 << 21 /* 2MiB */);
#else
  obm = std::make_shared<libstf::OutputBufferManager>(
      cthread, mem_config, pool, tlb, 40, 1 << 23 /* 8MiB */);
#endif
  obm->flush_buffers();

  if (num_decoders <= 0)
    num_decoders = column_chunk_config->num_decoders();

  auto hardware_reader = std::make_shared<parcore::fpga::PreloadFileReader>(
      cthread, pool, tlb, obm, column_chunk_config, page_config, meta, file);

  auto rows = meta.groups.size();
  assert(rows > 0);
  auto cols = meta.groups[0].chunks.size();

  for (size_t j = 0; j < cols; ++j) {
    auto first_column_chunk = meta.groups[0].chunks[j];
    auto typ = first_column_chunk.type;
    if (!parcore::metadata::is_libstf_type(typ))
      continue;
    for (size_t i = 0; i < rows; ++i) {

      size_t byte_size =
          libstf::size_of(parcore::metadata::to_libstf_type(typ));
      size_t in_bytes_plain = 0, in_bytes_hybrid = 0, out_bytes_plain = 0,
             out_bytes_hybrid = 0;
      size_t num_values_plain = 0, num_values_hybrid = 0;
      auto cc = meta.groups[i].chunks[j];
      assert(cc.type == typ);

      auto num_pages = 0;
      if (cc.dictionary != std::nullopt) {
        in_bytes_plain += cc.dictionary->size;
        num_pages += 1;
      }
      num_pages += cc.data.size();

      for (auto page : cc.data) {
        if (page.encoding == parcore::metadata::Encoding::PLAIN) {
          in_bytes_plain += page.size;
          out_bytes_plain += page.num_values * byte_size;
          num_values_plain += page.num_values;
        } else if (page.encoding == parcore::metadata::Encoding::HYBRID) {
          in_bytes_hybrid += page.size;
          out_bytes_hybrid += page.num_values * byte_size;
          num_values_hybrid += page.num_values;
        }
      }

      auto start = std::chrono::high_resolution_clock::now();
      for (size_t k = 0; k < reps; ++k) {
        auto handle = hardware_reader->decode_column_chunk(i, j);
        auto fpga_data = handle->get_next_stream_output(0);
#ifdef ENABLE_SIMULATION
        assert(!handle->stream_has_more_output(0));
        assert(!handle->any_stream_has_more_output());
        assert(fpga_data->size == (out_bytes_plain + out_bytes_hybrid));
#endif
      }
      auto end = std::chrono::high_resolution_clock::now();
      auto us =
          std::chrono::duration_cast<std::chrono::microseconds>(end - start)
              .count();

      us /= reps;
      bool compressed =
          cc.compression == parcore::metadata::Compression::SNAPPY;

      std::cout << path << "," << i << "," << j << "," << compressed << ","
                << num_pages << "," << in_bytes_plain << "," << in_bytes_hybrid
                << "," << out_bytes_plain << "," << out_bytes_hybrid << ","
                << num_values_plain << "," << num_values_hybrid << "," << us
                << std::endl;
    }
  }

  return EXIT_SUCCESS;
}
