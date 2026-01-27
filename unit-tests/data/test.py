import struct

def read_varint(buf, offset):
    """Decode LEB128-style varint, return (value, new_offset)."""
    result, shift = 0, 0
    while True:
        b = buf[offset]
        offset += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    return result, offset

def decode_rle_bitpacked(buf, bit_width):
    """Decode Parquet RLE/Bit-Packed Hybrid stream."""
    out, i = [], 0
    while i < len(buf):
        header, i = read_varint(buf, i)
        if header & 1 == 0:
            # ---- RLE run ----
            run_len = header >> 1
            val_bytes = (bit_width + 7) // 8
            val = int.from_bytes(buf[i:i+val_bytes], "little")
            i += val_bytes
            out.extend([val] * run_len)
        else:
            # ---- Bit-packed run ----
            num_groups = header >> 1
            total_vals = num_groups * 8
            bits_per_val = bit_width
            bitbuf = int.from_bytes(buf[i:i + (bits_per_val * total_vals + 7)//8], "little")
            i += (bits_per_val * total_vals + 7)//8
            for j in range(total_vals):
                out.append((bitbuf >> (j * bits_per_val)) & ((1 << bits_per_val) - 1))
    return out

# --- Example bytes (from your data) ---
data = bytes.fromhex("03000000a20201041400160118021a031c041e052006220724082609")

decoded = decode_rle_bitpacked(data, bit_width=8)
print(decoded)
