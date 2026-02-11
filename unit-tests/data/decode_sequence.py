import sys


def decode_bitpacked(buf: bytes, bit_width: int, num_values: int):
    values = []
    bit_buffer = 0
    bits_in_buffer = 0
    byte_idx = 0

    for _ in range(num_values):
        while bits_in_buffer < bit_width:
            bit_buffer |= buf[byte_idx] << bits_in_buffer
            bits_in_buffer += 8
            byte_idx += 1

        mask = (1 << bit_width) - 1
        value = bit_buffer & mask
        values.append(value)

        bit_buffer >>= bit_width
        bits_in_buffer -= bit_width

    return values


def main():
    if len(sys.argv) != 5:
        print("Usage: python decode_sequence.py <file> <bit_width> <offset> <length>")
        sys.exit(1)

    path = sys.argv[1]
    bit_width = int(sys.argv[2])
    offset = int(sys.argv[3])
    length = int(sys.argv[4])

    with open(path, "rb") as f:
        f.seek(offset)
        buf = f.read(length)

    # Each bit-packed run encodes 8 values per group
    total_bits = length * 8
    num_values = total_bits // bit_width

    values = decode_bitpacked(buf, bit_width, num_values)

    print("Decoded values:")
    print(values)


if __name__ == "__main__":
    main()
