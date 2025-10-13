import glob
import os

import pyarrow.parquet as pq
import fastparquet
import struct

# from pyarrow import decompress
# from snappy import snappy


def superficial_metadata(folder):
    print("Superficial Metadata: ----------------")
    parquet_files = glob.glob(f"{folder}/*.parquet")

    # Loop over them
    for file in parquet_files:
        # print(f"Processing file: {file}")
        # table = pq.read_table(filename)
        metadata = pq.read_metadata(file)
        row_group = metadata.row_group(0)

        print(f"{file.split('.')[0]}  Row Group {0} | Num Rows: {row_group.num_rows}:")

        # Iterate over columns
        for col_idx in range(row_group.num_columns):
            column = row_group.column(col_idx)
            print(f"  {str(column.physical_type):<15} |   {str(column.encodings):<25} {str(column.compression):<15} ")

    print("------------------------------------------------------------------")


def deep_dive_single_file(filepath):
    print("Deep Dive Single File: ----------------" + filepath)

    # Open the Parquet file to inspect metadata
    parquet_file = fastparquet.ParquetFile(filepath)
    pa_parquet_file = pq.read_table(filepath)
    pa_metadata = pq.read_metadata(filepath)
    # print(pa_parquet_file.to_pandas())
    print()
    print(pa_metadata.to_dict())
    for column in pa_metadata.to_dict()['row_groups'][0]['columns']:
        print(column)
    # print()

    for row_group_idx, (row_group, pa_row_group) in enumerate(zip(parquet_file.row_groups, pa_metadata.to_dict()['row_groups'])):
        print(f"Row Group {row_group_idx} | Num Rows: {row_group.num_rows}:")

        for col_idx, (column, pa_column) in enumerate(zip(row_group.columns, pa_row_group['columns'])):
            column_meta = column.meta_data

            print(f"  Column: {column_meta.path_in_schema} {column_meta.encodings}")
            # c_type_str = {
            #     0: "BOOLEAN",
            #     1: "INT32",
            #     2: "INT64",
            #     3: "INT96 (deprecated)",
            #     4: "FLOAT",
            #     5: "DOUBLE",
            #     6: "BYTE_ARRAY",
            #     7: "FIXED_LEN_BYTE_ARRAY"
            # }.get(column_meta.type, "UNKNOWN")

            print(f"    Physical Type: {pa_column['physical_type']:<15} | Uncompressed size: {pa_column['total_uncompressed_size']} bytes ({(pa_column['total_compressed_size'] / pa_column['total_uncompressed_size']) * 100:.1f} % compressed)")

            # Print encoding statistics if available
            if hasattr(column_meta, 'encoding_stats') and column_meta.encoding_stats:
                for stat in column_meta.encoding_stats:
                    page_type = stat.page_type
                    encoding = stat.encoding
                    count = stat.count

                    page_type_str = {0: "DATA_PAGE", 1: "INDEX_PAGE", 2: "DICTIONARY_PAGE"}.get(page_type, "UNKNOWN")
                    encoding_str = {
                        0: "PLAIN",
                        2: "PLAIN_DICTIONARY",
                        3: "RLE",
                        4: "BIT_PACKED",
                        5: "DELTA_BINARY_PACKED",
                        6: "DELTA_LENGTH_BYTE_ARRAY",
                        7: "DELTA_BYTE_ARRAY",
                        8: "RLE_DICTIONARY",
                        9: "BYTE_STREAM_SPLIT"
                    }.get(encoding, "UNKNOWN")

                    print(f"    {page_type_str:<15} | Encoding: {encoding_str:<15} | Count: {count}")



def complete_single_file(filepath):
    table = pq.read_table(filepath)
    print(table.schema)
    metadata = pq.read_metadata(filepath)
    # print(metadata)

    for row_group_idx in range(metadata.num_row_groups):
        row_group = metadata.row_group(row_group_idx)

        print(f"Row Group {row_group_idx} | Num Rows: {row_group.num_rows}:")

        # Iterate over columns
        for col_idx in range(row_group.num_columns):
            column = row_group.column(col_idx)
            print(f"  {str(column.physical_type):<15} |   {str(column.encodings):<25} {str(column.compression):<15} ")

            # print(f"  Column: {column.file_path} (Type: {column.physical_type})")
            # print(f"    Encodings: {column.encodings}")  # Encoding type
            # print(f"    Compression: {column.compression}")  # Compression type
            # print(f"    Total Size: Compressed {column.total_uncompressed_size}b | Uncompressed {column.total_compressed_size}b ")
            # print(f"    Offsets:  {column.data_page_offset}, {column.dictionary_page_offset}")


def raw_metadata(file_path):
    print("Raw Metadata: ----------------")
    with open(file_path, "rb") as f:
        f.seek(-8, 2)  # Seek to the last 8 bytes of the file
        footer_length = struct.unpack("<i", f.read(4))[0]  # Read footer length
        magic = f.read(4)  # Read magic bytes

        # Verify it is a Parquet file
        if magic != b"PAR1":
            raise ValueError("Not a valid Parquet file")

        # Read the footer metadata in binary
        f.seek(-(footer_length + 8), 2)
        metadata_binary = f.read(footer_length)

    print(f"File Metadata Size (bytes): {len(metadata_binary)}")
    print(f"Binary Footer Metadata: {metadata_binary[:100]}...")  # Print first 100 bytes as a sample

    parquet_file = pq.ParquetFile(file_path)

    # Iterate over row groups and columns
    for i in range(parquet_file.num_row_groups):
        row_group = parquet_file.metadata.row_group(i)
        print(f"\nRow Group {i}:")

        for j in range(row_group.num_columns):
            column_chunk = row_group.column(j)
            print(f"  Column {j}: {column_chunk.to_dict()}")
            print(f"    Total Uncompressed Bytes: {column_chunk.total_uncompressed_size}")
            print(f"    Total Compressed Bytes: {column_chunk.total_compressed_size}")
            # print(f"    Data Page Header Size (approx): {column_chunk}")

    pf = fastparquet.ParquetFile(file_path)

    # Iterate through row groups and column chunks
    for i, rg in enumerate(pf.row_groups):
        print(f"\nRow Group {i}:")
        for j, col in enumerate(rg.columns):
            print(f"  Column {j}: {col}")


output_folder = "./data/simulation"

# Function to generate binary and snappy file with 64-bit integers
# def generate_snappy_file(index, num_values):
#     filename_bin = f"{output_folder}/values{index:03}.bin"
#     filename_snappy = f"{output_folder}/values{index:03}.snappy"

#     # Create binary content: num_values of 64-bit unsigned integers
#     data = b''.join(struct.pack("<Q", (i + 1 + index * num_values)) for i in range(num_values))  # <Q = little-endian uint64
#     print(data[:16])
#     # Write raw binary
#     with open(filename_bin, "wb") as f:
#         f.write(data)

#     # Write snappy-compressed version
#     with open(filename_snappy, "wb") as f:
#         f.write(snappy.compress(data))

#     print(f"Generated: {filename_snappy} ({num_values} 64-bit integers)")


if __name__ == "__main__":
    # generate_snappy_file(0, 64)
    # generate_snappy_file(1, 64)
    os.makedirs(output_folder, exist_ok=True)

    # superficial_metadata("pyArrowParquet")
    # deep_dive_single_file("pyArrowParquet/customer.parquet")
    deep_dive_single_file("../../pyArrowVersion16Parquet/custom_forced.parquet")
    # deep_dive_single_file("pyArrowVersion16Parquet/custom_nodict.parquet")
    # raw_metadata("pyArrowParquet/customer.parquet")

    # print()
    # with open("pyArrowParquet/customer.parquet", "rb") as f:
    #     print(f.read(1000))  # Read first 100 bytes in hex

    # Read the compressed file
    # with open("pyArrowParquet/customer.parquet", "rb") as f:
    #     compressed_data = f.read()
    #
    # # Decompress it
    # decompressed_data = decompress(compressed_data)
    # print(decompressed_data[:100])



