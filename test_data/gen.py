import random

import snappy
import thriftpy2
from thriftpy2.protocol import TCompactProtocolFactory
from thriftpy2.transport import TMemoryBuffer
import struct
import os
import pyarrow as pa
import pyarrow.parquet as pq

from metadata import deep_dive_single_file

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
}


def make_boolean_rle_parquet(path):
    # Boolean RLE encoded column
    data = [
        True, False, False, False, False, False, True, False,
        True, False, False, False, False, True, False, False,
        True, False, False, False, False, True, True, False,
        True, False, False, False, True, False, False, False,
        True, False, False, False, True, False, True, False,
        True, False, False, False, True, True, False, False,
        True, False, False, False, True, True, True, False,
        True, False, False, True, False, False, False, False,
        True, False, True, False, False, False, True, False,
        True, False, True, False, False, True, False, False,
        True, False, True, False, False, True, True, False,
        True, False, True, False, True, False, False, False,
        True, False, True, False, True, False, True, False,
        True, False, True, False, True, True, False, False,
        True, False, True, False, True, True, True, False,
        True, False, True, True, False, False, False, False,
    ]
    array = pa.array(data, type=pa.bool_())
    field = pa.field('bool_col', pa.bool_(), nullable=False)
    table = pa.Table.from_arrays([array], schema=pa.schema([field]))
    pq.write_table(table, path,
                   use_dictionary=False,
                   compression=None,
                   # column_encoding='RLE',
                   data_page_version='1.0')


def make_4byte_dict_parquet(path, use_dict=True, less=0, append=None):
    # 4-byte dictionary encoded (e.g., INT32)
    # data = np.random.randint(0, 3, 100).astype(np.int32)
    # array = pa.DictionaryArray.from_arrays(pa.array(data), pa.array([0, 1, 2]))
    # field = pa.field('int_col', pa.dictionary(pa.int32(), pa.int32()))
    # schema = pa.schema([field])
    # table = pa.Table.from_arrays([array], schema=schema)
    # pq.write_table(table, path, use_dictionary=True, compression=None, data_page_version='1.0')
    data = [
        0x7110011f, 0x7120012f, 0x7120012f, 0x7140014f, 0x7150015f, 0x7120012f, 0x7120012f, 0x7180018f,
        0x7210021f, 0x7220022f, 0x7230023f, 0x7220022f, 0x7220022f, 0x7260026f, 0x7220022f, 0x7280028f,
        0x7310031f, 0x7320032f, 0x7330033f, 0x7320032f, 0x7320032f, 0x7360036f, 0x7320032f, 0x7380038f,
        0x7410041f, 0x7420042f, 0x7430043f, 0x7420042f, 0x7420042f, 0x7460046f, 0x7420042f, 0x7480048f,
    ]
    if append:
        data.extend(append)
    array = pa.array(data[:-less] if less else data, type=pa.int32())
    field = pa.field('int32_col', pa.int32(), nullable=False)
    schema = pa.schema([field])
    table = pa.Table.from_arrays([array], schema=schema)

    pq.write_table(
        table,
        path,
        use_dictionary=use_dict,
        compression=None,
        data_page_version='1.0'
    )


def make_8byte_dict_parquet(path, use_dict=True, less=0):
    # 8-byte dictionary encoded (e.g., INT64)
    # unique_values = [10000000000, 20000000000, 30000000000]
    # data = np.random.choice(unique_values, 100)
    # array = pa.array(data, type=pa.int64())
    # table = pa.Table.from_arrays([array], names=['int64_col'])
    # pq.write_table(table, path, use_dictionary=True, compression=None, data_page_version='1.0')
    data = [
        0x71100000011f, 0x71200000012f, 0x71200000012f, 0x71400000014f, 0x71500000015f, 0x71200000012f, 0x71200000012f, 0x71800000018f,
        0x72100000021f, 0x72200000022f, 0x72300000023f, 0x72200000022f, 0x72200000022f, 0x72600000026f, 0x72200000022f, 0x72800000028f,
        0x73100000031f, 0x73200000032f, 0x73300000033f, 0x73200000032f, 0x73200000032f, 0x73600000036f, 0x73200000032f, 0x73800000038f,
        0x74100000041f, 0x74200000042f, 0x74300000043f, 0x74200000042f, 0x74200000042f, 0x74600000046f, 0x74200000042f, 0x74800000048f,
    ]
    field = pa.field('int64_col', pa.int64(), nullable=False)
    array = pa.array(data[:-less] if less else data, type=pa.int64())
    schema = pa.schema([field])
    table = pa.Table.from_arrays([array], schema=schema)

    pq.write_table(
        table,
        path,
        use_dictionary=use_dict,
        compression=None,
        data_page_version='1.0'
    )


parquet_thrift = thriftpy2.load("parquet.thrift", module_name="parquet_thrift")


def read_page_header_and_size(data):
    trans = TMemoryBuffer(data)
    proto = TCompactProtocolFactory().get_protocol(trans)
    header = parquet_thrift.PageHeader()
    header.read(proto)
    header_size = len(data) - len(trans.getvalue())
    return header, header_size


def thrift_serialize_compact(thrift_obj):
    trans = TMemoryBuffer()
    proto = TCompactProtocolFactory().get_protocol(trans)
    thrift_obj.write(proto)
    return trans.getvalue()


def extract_encoded_sections_only(parquet_path, output_dir, remove_header=True, value_offset=0):
    pf = pq.ParquetFile(parquet_path)
    os.makedirs(output_dir, exist_ok=True)

    with open(parquet_path, "rb") as f:
        page_idx = value_offset

        for rg_index in range(pf.metadata.num_row_groups):
            row_group = pf.metadata.row_group(rg_index)

            for col_index in range(row_group.num_columns):
                col = row_group.column(col_index)

                # ---- Dictionary Page ----
                if col.dictionary_page_offset is not None:
                    f.seek(col.dictionary_page_offset)
                    dict_page_data = f.read(col.data_page_offset - col.dictionary_page_offset)
                    header, header_size = read_page_header_and_size(dict_page_data)
                    encoded = dict_page_data[header_size:header_size + header.compressed_page_size]
                    serialized = thrift_serialize_compact(header)

                    # Get actual encoding from header
                    print("Dictionary page header:", header)
                    print("Header", dict_page_data[:header_size].hex())
                    print("Header", dict_page_data[header_size:][::-1].hex())
                    encoding = encoding_str.get(header.dictionary_page_header.encoding, "UNKNOWN")
                    filename = f"values{page_idx:03}_DICTIONARY_PAGE_{encoding}_h{0 if remove_header else format(header_size, 'x')}.bin"
                    with open(os.path.join(output_dir, filename), "wb") as out:
                        out.write(encoded if remove_header else dict_page_data)
                    print(f"✅ Wrote {filename}")
                    page_idx += 1

                # ---- Data Page ----
                f.seek(col.data_page_offset)
                data = f.read(col.total_compressed_size)
                header, header_size = read_page_header_and_size(data)
                encoded = data[header_size:header_size + header.compressed_page_size]

                # Get actual encoding from page header
                print("Data page header:", header)
                print("Header", data[:header_size].hex())
                print("Header", data[header_size:][::-1].hex())
                if header.type == 0:
                    encoding = encoding_str.get(header.data_page_header.encoding, "UNKNOWN")
                elif header.type == 3:
                    encoding = encoding_str.get(header.data_page_header_v2.encoding, "UNKNOWN")
                else:
                    encoding = "UNKNOWN"

                filename = f"values{page_idx:03}_DATA_PAGE_{encoding}_h{0 if remove_header else format(header_size, 'x')}.bin"
                with open(os.path.join(output_dir, filename), "wb") as out:
                    out.write(encoded if remove_header else data)
                print(f"✅ Wrote {filename}")
                page_idx += 1


def generate_test_patterns(count, byte_width):
    base_patterns = [
        0x01, 0x02, 0x03, 0x04,
        0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c,
        0x0d, 0x0e, 0x0f, 0x10,
        0x91, 0x92, 0x93, 0x94,
        0x95, 0x96, 0x97, 0x98,
        0x99, 0x9a, 0x9b, 0x9c,
        0x9d, 0x9e, 0x9f, 0xa0,
    ]

    result = []
    max_value = (1 << (byte_width * 8)) - 1
    print(f"\nGenerated {count} values ({byte_width * 8}-bit each):")
    for i in range(count):
        pattern = 0xf0
        byte = base_patterns[i % len(base_patterns)]

        pattern = (pattern << (8 * int(byte_width/2))) | byte
        rest = byte_width - int(byte_width/2) - 1
        pattern = (pattern << (8 * rest)) | 0x0a
        pattern &= max_value
        result.append(pattern)
        print(f"{i:03}: 0x{pattern:0{byte_width * 2}X}")
    return result


def load_and_print_values(bin_path, byte_width):
    try:
        with open(bin_path, "rb") as f:
            data = f.read()

        values = []

        if byte_width == 1:
            # Interpret as array of booleans (RLE may still apply though)
            values = list(data)
            print(f"[bool/raw byte] Values: {values}")

        elif byte_width == 4:
            # Interpret as little-endian int32
            num_items = len(data) // 4
            values = list(struct.unpack(f"<{num_items}i", data))
            print(f"[int32] Values: {values}")

        elif byte_width == 8:
            # Interpret as little-endian int64
            num_items = len(data) // 8
            values = list(struct.unpack(f"<{num_items}q", data))
            print(f"[int64] Values: {values}")

        else:
            raise ValueError(f"Unsupported byte width: {byte_width}")

        return values
    except Exception:
        print('Read error file:', bin_path)


def write_binary_file(filename, values, byte_width):
    with open(filename, 'wb') as f:
        for val in values:
            f.write(val.to_bytes(byte_width, byteorder='big'))


# def write_snappy_file(input_file, output_file):
#     with open(input_file, 'rb') as f:
#         data = f.read()
#     compressed = snappy.compress(data)
#     with open(output_file, 'wb') as f:
#         f.write(compressed)

#     print(f"\nCompression Stats:")
#     print(f"Original size:   {len(data)} bytes")
#     print(f"Compressed size: {len(compressed)} bytes")
#     print(f"Compression ratio: {len(compressed) / len(data):.2f}")


def generate_test_data(length):
    """
    Generate consistent test data for all columns.
    This ensures all calls to generate_test_parquet use the same data pattern.
    """
    # Value pools
    bool_vals = [True, False]
    int_vals = [0, 1, 2, 10, 20, 100, 5, 15, 25, 32, 64, 1000, 100000, 54321, -1]
    float_vals = [0.0, 1.1, 2.2, 10.5, 20.25, 100.75, 100.785, 0.0025, 1.3, 12.134, 3.1415, 0.0123456789, 12345678, 13579]

    # Sample once for consistent debugging - use the first 'length' values from each pool
    # This ensures all columns use the same data pattern for easier debugging
    bool_sample = [random.choice(bool_vals) for _ in range(length)]
    int_sample = [random.choice(int_vals) for _ in range(length)]
    float_sample = [random.choice(float_vals) for _ in range(length)]
    
    # Take exactly 'length' values from each sample
    bool_sample = bool_sample[:length]
    int_sample = int_sample[:length]
    float_sample = float_sample[:length]
    
    return {
        'bool': bool_sample,
        'int': int_sample,
        'float': float_sample
    }


def generate_test_parquet(path, test_data, compression=None, use_dict=True, data_page_size=256 * 1024, row_group_size=1024*1024):
    """
    Generate a test Parquet file using pre-generated test data.
    
    Args:
        path: Output file path
        test_data: Dictionary with 'bool', 'int', 'float' keys containing pre-generated data arrays
        compression: Compression type (default: None)
        use_dict: Whether to use dictionary encoding (default: True)
        data_page_size: Data page size in bytes (default: 256KB)
        row_group_size: Row group size in bytes (default: 1MB)
    """
    # Use the pre-generated test data instead of generating new random data
    length = len(test_data['int'])  # Get length from the test data
    
    # Define columns and desired encodings using the test data
    columns = [
        ("int32_col",    test_data['int'],    pa.int32(),    False),
        ("int64_col",    test_data['int'],    pa.int64(),    False),
        ("bool_col",      test_data['bool'],   pa.bool_(),    False),
        ("float32_col",  test_data['float'],  pa.float32(),  False),
        ("float64_col",  test_data['float'],  pa.float64(),  False),
    ]

    arrays = []
    fields = []

    for name, values, dtype, nullable in columns:
        # Use the pre-sampled values instead of random.choice for consistent debugging
        arrays.append(pa.array(values, type=dtype))
        fields.append(pa.field(name, dtype, nullable=nullable))

    schema = pa.schema(fields)
    table = pa.Table.from_arrays(arrays, schema=schema)

    pq.write_table(
        table,
        path,
        use_dictionary=use_dict,  # Still required for dictionary to be allowed
        compression=compression,
        data_page_version='1.0',
        data_page_size=data_page_size,
        row_group_size=row_group_size
        # column_encoding=column_encodings  # 👈 new magic here
    )
    print(f"Wrote file {path}")


def generate_column_data(values, length, dtype):
    sampled = [random.choice(values) for _ in range(length)]
    return pa.array(sampled, type=dtype)


def inspect_parquet_compression(path):
    metadata = pq.read_metadata(path)
    num_row_groups = metadata.num_row_groups
    total_uncompressed = 0
    total_compressed = 0

    print(f"Inspecting Parquet file: {path}")
    print(f"Number of row groups: {num_row_groups}")
    print(f"Number of columns: {metadata.num_columns}\n")

    for rg in range(num_row_groups):
        row_group = metadata.row_group(rg)
        print(f"Row Group {rg}:")
        for col in range(row_group.num_columns):
            column = row_group.column(col)
            uncompressed = column.total_uncompressed_size
            compressed = column.total_compressed_size
            codec = column.compression

            total_uncompressed += uncompressed
            total_compressed += compressed

            print(f"  Column {col} ({column.path_in_schema}):")
            print(f"    Compression: {codec}")
            print(f"    Uncompressed size: {uncompressed} bytes")
            print(f"    Compressed size:   {compressed} bytes")
            ratio = (1 - compressed / uncompressed) if uncompressed else 0
            print(f"    Compression ratio: {ratio:.2%}\n")

    print("===")
    print(f"Total uncompressed size: {total_uncompressed} bytes")
    print(f"Total compressed size:   {total_compressed} bytes")
    if total_uncompressed:
        overall_ratio = 1 - (total_compressed / total_uncompressed)
        print(f"Overall compression ratio: {overall_ratio:.2%}")
    else:
        print("Warning: total uncompressed size is 0.")



if __name__ == "__main__":
    # Parameters
    byte_width = 8  # Value size in bytes (1 to 8)
    num_packets = 3  # Number of AXI packets (512 bits = 64 bytes each)

    values_per_packet = 64 // byte_width
    total_values = num_packets * values_per_packet


    # Generate values and write files
    # values = generate_test_patterns(total_values, byte_width)
    # plain_filename = "simulation/values000.bin"
    # snappy_filename = "simulation/values000.snappy"
    # write_binary_file(plain_filename, values, byte_width)
    # write_snappy_file(plain_filename, snappy_filename)
    # plain_filename = "simulation/values001.bin"
    # snappy_filename = "simulation/values001.snappy"
    # write_binary_file(plain_filename, values[:-2], byte_width)
    # write_snappy_file(plain_filename, snappy_filename)

    # print(f"\nAXI Packet Configuration:")
    # print(f"- Packet width: 512 bits (64 bytes)")
    # print(f"- Value width:  {byte_width * 8} bits")
    # print(f"- Values/packet: {values_per_packet}")
    # print(f"- Total packets: {num_packets}")
    # print(f"- Total values:  {total_values}")

    # print(f"\nFiles written:")
    # print(f"- Plain binary:  {plain_filename}")
    # print(f"- Snappy binary: {snappy_filename}")

    print("\nMaking parquet files:")
    make_boolean_rle_parquet("boolean_rle.parquet")
    make_4byte_dict_parquet("int32_dict.parquet")
    make_4byte_dict_parquet("int32_plain.parquet", False)
    make_4byte_dict_parquet("int32_bigger_plain.parquet", False, 0, [0x7520052f, 0x7580058f])
    make_8byte_dict_parquet("int64_dict.parquet")
    make_8byte_dict_parquet("int64_plain.parquet", False)
    deep_dive_single_file("boolean_rle.parquet")
    deep_dive_single_file("int32_dict.parquet")
    deep_dive_single_file("int64_dict.parquet")
    extract_encoded_sections_only("boolean_rle.parquet", "simulation/bool_pages", True)
    extract_encoded_sections_only("int32_plain.parquet", "simulation/int32_pages", True)
    extract_encoded_sections_only("int32_bigger_plain.parquet", "simulation/int32_pages", True, 1)
    extract_encoded_sections_only("int32_dict.parquet", "simulation/int32_pages", True)
    extract_encoded_sections_only("int64_plain.parquet", "simulation/int64_pages", True)
    extract_encoded_sections_only("int64_dict.parquet", "simulation/int64_pages", True)
    load_and_print_values('simulation/bool_pages/values000_DATA_PAGE_PLAIN_h22.bin', 1)
    # load_and_print_values('simulation/bool_pages/values000_DATA_PAGE_RLE.bin', 1)
    # load_and_print_values('simulation/int32_pages/values000_DATA_PAGE_PLAIN_h2f.bin', 4)
    load_and_print_values('simulation/int32_pages/values000_DATA_PAGE_PLAIN_h2f.bin', 1)
    load_and_print_values('simulation/int32_pages/values000_DICTIONARY_PAGE_PLAIN_h10.bin', 1)
    load_and_print_values('simulation/int32_pages/values001_DATA_PAGE_RLE_DICTIONARY_h2d.bin', 1)
    load_and_print_values('simulation/int64_pages/values000_DATA_PAGE_PLAIN_h3f.bin', 1)
    load_and_print_values('simulation/int64_pages/values000_DICTIONARY_PAGE_PLAIN_h10.bin', 1)
    load_and_print_values('simulation/int64_pages/values001_DATA_PAGE_RLE_DICTIONARY_h3d.bin', 1)

    sizes = [32, 128, 1024, 8192]
    # Generate test data once for consistent debugging across all files
    test_data = generate_test_data(max(sizes))  # Use max size to cover all cases
    print(f"\n=== Generated consistent test data for all files ===")
    print(f"Total data points: {len(test_data['bool'])}")
    print(f"Bool pattern: {test_data['bool'][:10]}...")
    print(f"Int pattern: {test_data['int'][:10]}...")
    print(f"Float pattern: {test_data['float'][:10]}...")
    print(f"All files will use the same data pattern for easier debugging\n")
    
    for num_rows in sizes:
        # Use the same test data for all files, just truncate to the required length
        current_test_data = {
            'bool': test_data['bool'][:num_rows],
            'int': test_data['int'][:num_rows],
            'float': test_data['float'][:num_rows]
        }
        
        generate_test_parquet(f"test_{num_rows}.parquet", current_test_data)
        generate_test_parquet(f"test_{num_rows}_snappy.parquet", current_test_data, compression='snappy')
        generate_test_parquet(f"test_{num_rows}_no_dict.parquet", current_test_data, use_dict=False)
        generate_test_parquet(f"test_{num_rows}_no_dict_snappy.parquet", current_test_data, compression='snappy', use_dict=False)
        generate_test_parquet(f"test_{num_rows}_small.parquet", current_test_data, use_dict=True, data_page_size=1024, row_group_size=16*1024)

    deep_dive_single_file("test_8192_small.parquet")
    # deep_dive_single_file("test_1000000_snappy.parquet")
    # deep_dive_single_file("test_1000000_no_dict_snappy.parquet")
    # inspect_parquet_compression("test_1000000_snappy.parquet")
    print(test_data['bool'])
    print(test_data['int'])
    print(test_data['float'])
