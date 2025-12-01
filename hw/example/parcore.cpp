#include "parcore.hpp"

#include <arrow/array.h>
#include <arrow/chunked_array.h>
#include <arrow/io/file.h>
#include <arrow/util/compression.h>
#include <memory>
#include <parquet/arrow/reader.h>
#include <parquet/column_page.h>
#include <parquet/column_reader.h>
#include <parquet/metadata.h>
#include <parquet/platform.h>
#include <parquet/types.h>
#include <string>

namespace parcore {

Type data_type(parquet::Type::type data_type) {
  switch (data_type) {
  case parquet::Type::type::BOOLEAN:
    return Type::BYTE_T;
  case parquet::Type::type::INT32:
    return Type::INT32_T;
  case parquet::Type::type::INT64:
    return Type::INT64_T;
  case parquet::Type::type::FLOAT:
    return Type::FLOAT_T;
  case parquet::Type::type::DOUBLE:
    return Type::DOUBLE_T;
  default:
    throw std::runtime_error("Invalid parquet type for parcore: " +
                             std::to_string(data_type));
  }
}

std::vector<Column> read_parquet_pages(const std::string &filepath) {
  auto input_result = arrow::io::ReadableFile::Open(filepath);
  if (!input_result.ok()) {
    throw std::runtime_error("Failed to open file: " +
                             input_result.status().ToString());
  }
  auto input = *input_result;

  auto reader = parquet::ParquetFileReader::Open(input);
  auto metadata = reader->metadata();
  std::vector<Column> all_columns;

  for (int rg = 0; rg < metadata->num_row_groups(); rg++) {
    auto rg_reader = reader->RowGroup(rg);
    auto rg_meta = metadata->RowGroup(rg);

    for (int col = 0; col < rg_meta->num_columns(); col++) {
      auto page_reader = rg_reader->GetColumnPageReader(col);
      auto col_meta = rg_reader->Column(col);
      auto col_chunk_meta = rg_meta->ColumnChunk(col);

      // Read entire column chunk once
      std::unique_ptr<parquet::arrow::FileReader> arrow_reader;
      parquet::arrow::FileReaderBuilder builder;
      PARQUET_THROW_NOT_OK(builder.Open(input));
      PARQUET_THROW_NOT_OK(builder.Build(&arrow_reader));

      std::shared_ptr<arrow::ChunkedArray> chunked_array;
      PARQUET_THROW_NOT_OK(
          arrow_reader->RowGroup(rg)->Column(col)->Read(&chunked_array));

      Column column;
      column.id = col;
      column.name = col_meta->descr()->name();
      if (col_chunk_meta->compression() ==
          parquet::Compression::type::UNCOMPRESSED) {
        column.compression = Compression::RAW;
      } else if (col_chunk_meta->compression() ==
                 parquet::Compression::type::SNAPPY) {
        column.compression = Compression::SNAPPY;
      } else {
        throw std::runtime_error("Column compression other than RAW (none), "
                                 "SNAPPY is not supported");
      }
      column.data_type = data_type(rg_meta->ColumnChunk(col)->type());

      int64_t offset = 0;
      std::shared_ptr<parquet::Page> page;
      while ((page = page_reader->NextPage()) != nullptr) {
        Page p;
        p.data.assign(page->data(), page->data() + page->size());
        if (column.compression == Compression::SNAPPY) {
          auto codec = arrow::util::Codec::Create(arrow::Compression::SNAPPY)
                           .ValueOrDie();
          int64_t max_compressed_size =
              codec->MaxCompressedLen(p.data.size(), p.data.data());
          std::vector<uint8_t> compressed(max_compressed_size);
          auto compress_result =
              codec->Compress(p.data.size(), p.data.data(), max_compressed_size,
                              compressed.data());
          if (!compress_result.ok()) {
            throw std::runtime_error("Compression failed");
          }
          int64_t compressed_size = *compress_result;
          compressed.resize(compressed_size);
          p.data = std::move(compressed);
        }

        if (page->type() == parquet::PageType::DICTIONARY_PAGE) {
          p.num_values = 0;
          column.dictionary = std::move(p);
        } else if (page->type() == parquet::PageType::DATA_PAGE) {
          auto pagev1 = std::static_pointer_cast<parquet::DataPageV1>(page);
          p.num_values = pagev1->num_values();
          auto slice = chunked_array->Slice(offset, p.num_values);
          for (const auto &chunk : slice->chunks()) {
            auto buffer = chunk->data()->buffers[1];
            p.values.insert(p.values.end(), buffer->data(),
                            buffer->data() + buffer->size());
          }
          offset += p.num_values;
          column.pages.push_back(std::move(p));
        } else if (page->type() == parquet::PageType::DATA_PAGE_V2) {
          throw std::runtime_error("Page v2 pages are not supported");
        }
      }

      all_columns.push_back(std::move(column));
    }
  }

  return all_columns;
}

cmd_t cmd(PageType page_type, Type data_type, uint32_t num_values,
          Compression compression) {
  std::array<uint8_t, 64> b = {0};

  b[41] = static_cast<uint8_t>(page_type);
  b[42] = static_cast<uint8_t>(data_type);

  if (page_type == PageType::HYBRID) {
    std::memcpy(&b[43], &num_values, sizeof(num_values));
  }

  b[47] = static_cast<uint8_t>(compression);

  return b;
}

uint32_t data_size(Type data_type) {
  switch (data_type) {
  case Type::BYTE_T:
    return 1;
  case Type::INT32_T:
  case Type::FLOAT_T:
    return 4;
  case Type::INT64_T:
  case Type::DOUBLE_T:
    return 8;
  default:
    throw std::runtime_error("Unexpected parcore type");
  }
}

} // namespace parcore
