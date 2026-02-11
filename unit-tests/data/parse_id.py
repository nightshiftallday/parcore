import sys


def split_bits_from_hex(hex_string: str, bit_width: int = 18):
    # Convert hex → integer
    n = int(hex_string, 16)

    # Total bits in the original hex (preserve full width incl. leading zeros)
    total_bits = len(hex_string) * 4

    values = []
    mask = (1 << bit_width) - 1

    # This naturally walks LSB-first (equivalent to your reversed bit list)
    for offset in range(0, total_bits, bit_width):
        if offset + bit_width > total_bits:
            break
        value = (n >> offset) & mask
        values.append(value)

    return values


def main():
    if len(sys.argv) not in (2, 3):
        print("Usage: python parse_id.py <hex_string> [bit_width]")
        sys.exit(1)

    hex_string = sys.argv[1]
    bit_width = int(sys.argv[2]) if len(sys.argv) == 3 else 18

    values = split_bits_from_hex(hex_string, bit_width)

    for i, v in enumerate(values):
        print(i, v)


if __name__ == "__main__":
    main()
