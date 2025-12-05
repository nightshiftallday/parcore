#include "parcore.hpp"

#include <boost/program_options.hpp>
#include <boost/program_options/value_semantic.hpp>
#include <cDefs.hpp>
#include <chrono>
#include <coyote/cThread.hpp>
#include <cstdlib>
#include <cstring>
#include <memory>

// Constants
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 32

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this
// is the only possible value
#define DEFAULT_VFPGA_ID 0

const std::string separator = std::string(80, '-');

typedef std::vector<uint8_t> hex_t;

std::ostream &operator<<(std::ostream &os, const hex_t &arr) {
  std::ios_base::fmtflags f(os.flags());
  for (auto byte : arr)
    os << std::hex << std::setw(2) << std::setfill('0') << (int)byte;
  os.flags(f);
  return os;
}

// Allow printing cmd
std::ostream &operator<<(std::ostream &os, const parcore::cmd_t &arr) {
  std::ios_base::fmtflags f(os.flags());
  for (auto byte : arr)
    os << std::hex << std::setw(2) << std::setfill('0') << (int)byte << " ";
  os.flags(f);
  return os;
}

void diff(std::vector<uint8_t> &a, std::vector<uint8_t> &b,
          parcore::Type data_type) {
  auto l = parcore::data_size(data_type);
  size_t len = std::min(a.size(), b.size());
  bool match = true;
  for (size_t i = 0; i < len / l; ++i) {
    auto a_val = hex_t(a.begin() + i * l, a.begin() + (i + 1) * l);
    auto b_val = hex_t(b.begin() + i * l, b.begin() + (i + 1) * l);
    if (a_val != b_val) {
      std::cout << "\t\tinvalid value at " << i << ": got " << a_val
                << ", expected " << b_val << std::endl;
      match = false;
    }
  }
  if (a.size() != b.size()) {
    std::cout << "\t\tlength mismatch: got " << a.size() << " bytes, expected "
              << b.size() << " bytes" << std::endl;
    match = false;
  }

  if (match)
    std::cout << "\t\tresult is correct!" << std::endl;
}

void send_page(std::shared_ptr<coyote::cThread> coyote_thread,
               parcore::Type data_type, parcore::Page page) {
  coyote::localSg src_sg, dst_sg;
  if (coyote_thread != nullptr) {
    auto src_len = static_cast<uint32_t>(page.data.size());
    auto src_mem = (uint8_t *)coyote_thread->getMem(
        {coyote::CoyoteAllocType::REG, src_len});
    if (!src_mem) {
      throw std::runtime_error("Could not allocate src memory");
    }
    memcpy(src_mem, page.data.data(), src_len);
    src_sg = {
        .addr = src_mem,
        .len = src_len,
        .stream = coyote::STRM_HOST,
        .dest = 1,
    };
    std::cout << "\t\tsrc allocation: at " << src_sg.addr << ", len "
              << src_sg.len << std::endl;
  } else {
    std::cout << "\t\tcontents: " << hex_t(page.data) << std::endl;
  }

  if (coyote_thread != nullptr) {
    if (page.num_values > 0) {
      auto dst_len = parcore::data_size(data_type) * page.num_values;
      auto dst_mem = (uint8_t *)coyote_thread->getMem(
          {coyote::CoyoteAllocType::REG, dst_len});
      if (!dst_mem) {
        throw std::runtime_error("Could not allocate dst memory");
      }
      memset(dst_mem, 0, dst_len);
      dst_sg = {
          .addr = dst_mem,
          .len = dst_len,
          .stream = coyote::STRM_HOST,
          .dest = 0,
      };
      std::cout << "\t\tdst allocation: at " << dst_sg.addr << ", len "
                << dst_sg.len << std::endl;
    } else {
      std::cout << "\t\tdst allocation: none" << std::endl;
    }

    coyote_thread->clearCompleted();
  }

  std::cout << "\t\tprocessing page..." << std::flush;
  auto start = std::chrono::high_resolution_clock::now();
  int iters = 0;
  if (coyote_thread != nullptr) {
    if (page.num_values > 0) {
      coyote_thread->invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg, dst_sg);
      while (coyote_thread->checkCompleted(
                 coyote::CoyoteOper::LOCAL_TRANSFER) != 1)
        ++iters;
    } else {
      coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ, src_sg);
      while (coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1)
        ++iters;
    }
  }
  auto ms = std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::high_resolution_clock::now() - start)
                .count();
  std::cout << "\t\tcompleted! took " << ms << "ns, " << iters << " iterations"
            << std::endl;

  if (coyote_thread != nullptr && page.num_values > 0) {
    std::vector<uint8_t> result;
    auto addr = static_cast<uint8_t *>(dst_sg.addr);
    result.assign(addr, addr + dst_sg.len);
    diff(result, page.values, data_type);
  }
}

void process(std::shared_ptr<coyote::cThread> coyote_thread,
             parcore::PageType page_type, parcore::Type data_type,
             parcore::Compression compression, parcore::Page page) {
  auto cmd_bytes = cmd(page_type, data_type, page.num_values, compression);
  std::cout << "\t\tcmd: " << cmd_bytes << std::endl;

  if (coyote_thread != nullptr) {
    auto cmd_len = static_cast<uint32_t>(cmd_bytes.size());
    auto cmd_mem = (uint8_t *)coyote_thread->getMem(
        {coyote::CoyoteAllocType::REG, cmd_len});
    if (!cmd_mem) {
      throw std::runtime_error("Could not allocate cmd memory");
    }
    memcpy(cmd_mem, cmd_bytes.data(), cmd_len);
    coyote::localSg cmd_sg = {
        .addr = cmd_mem,
        .len = cmd_len,
        .stream = coyote::STRM_HOST,
        .dest = 0,
    };
    std::cout << "\t\tcmd allocation: at " << cmd_sg.addr << ", len "
              << cmd_sg.len << std::endl;

    std::cout << "\t\tsending command..." << std::flush;
    auto start = std::chrono::high_resolution_clock::now();
    int iters = 0;
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ, cmd_sg);
    while (coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1)
      ++iters;
    auto ms = std::chrono::duration_cast<std::chrono::nanoseconds>(
                  std::chrono::high_resolution_clock::now() - start)
                  .count();
    std::cout << "\t\tcompleted! took " << ms << "ns, " << iters
              << " iterations" << std::endl;
  }

  send_page(coyote_thread, data_type, page);
}

int main(int argc, char *argv[]) {
  std::string parquet_file;
  bool dry_run;
  int limit;

  boost::program_options::options_description runtime_options(
      "Parcore example");
  runtime_options.add_options()(
      "file,f", boost::program_options::value<std::string>(&parquet_file),
      "Path to the parquet file to parse")(
      "dry-run,d", boost::program_options::bool_switch(&dry_run),
      "Don't send data to the FPGA, just print the that that *would* be sent.")(
      "limit,l", boost::program_options::value<int>(&limit),
      "Limit how many columns to process out of the file");
  boost::program_options::variables_map command_line_arguments;
  boost::program_options::store(
      boost::program_options::parse_command_line(argc, argv, runtime_options),
      command_line_arguments);
  boost::program_options::notify(command_line_arguments);

  std::shared_ptr<coyote::cThread> coyote_thread;
  if (!dry_run) {
    coyote_thread =
        std::make_shared<coyote::cThread>(DEFAULT_VFPGA_ID, getpid());
  }

  auto columns = parcore::read_parquet_pages(parquet_file);
  int i = 0;
  for (auto column : columns) {
    std::cout << separator << std::endl;
    std::cout << "Decoding column " << column.name << " (#" << i
              << "):" << std::endl;
    std::cout << "\tcompression: " << column.compression << std::endl;
    std::cout << "\tdata_type type: " << column.data_type << std::endl;
    std::cout << "\tDictionary:" << std::endl;
    std::cout << "\t\tcompressed size: " << column.dictionary.data.size()
              << " bytes (" << column.compression << " compression)"
              << std::endl;

    process(coyote_thread, parcore::PageType::DICT, column.data_type,
            column.compression, column.dictionary);

    int j = 0;
    for (auto page : column.pages) {
      std::cout << "\tData page " << j << ":" << std::endl;
      std::cout << "\t\tcompressed size: " << page.data.size() << " bytes"
                << std::endl;
      std::cout << "\t\tnumber of values: " << page.num_values << std::endl;

      process(coyote_thread, parcore::PageType::HYBRID, column.data_type,
              column.compression, page);
    }

    ++i;
    if (i >= limit) {
      std::cout << "reached limit " << limit << std::endl;
      break;
    }
  }

  return EXIT_SUCCESS;
}
