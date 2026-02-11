import struct
import sys


def read_uleb128(data, offset):
    result = 0
    shift = 0

    while True:
        b = data[offset]
        offset += 1
        result |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            break
        shift += 7

    return result, offset


def parse_file(path):
    with open(path, "rb") as f:
        data = f.read()

    # ---- Skip metadata ----
    meta_len = struct.unpack_from("<I", data, 0)[0]
    offset = 4 + meta_len

    if offset >= len(data):
        raise ValueError("Invalid metadata length")

    # ---- Read bit width ----
    bit_width = data[offset]
    offset += 1

    print(f"Bit width: {bit_width}")
    print()

    # ---- Parse hybrid stream ----
    while offset < len(data):
        segment_start = offset

        header, offset = read_uleb128(data, offset)

        if header & 1:
            # Bit-packed
            groups = header >> 1
            num_values = groups * 8
            total_bits = num_values * bit_width
            total_bytes = (total_bits + 7) // 8
            offset += total_bytes
            enc = "BPE"
        else:
            # RLE
            num_values = header >> 1
            value_bytes = (bit_width + 7) // 8
            offset += value_bytes
            enc = "RLE"

        print(f"Offset {segment_start} | {enc} | Length {num_values}")

    print(f"offest={offset}, len={len(data)}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python print_sequence.py <file>")
        sys.exit(1)

    parse_file(sys.argv[1])
