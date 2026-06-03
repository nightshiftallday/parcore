`include "lynx_macros.svh"

package parcore;

import libstf::*;
import lynxTypes::*;

parameter int VARINT_NUM_BYTES = 4;
parameter int VARINT_NUM_BITS = VARINT_NUM_BYTES * 7;
// This is intentionally 1 bit wider to allow encoding the case in which
// all bytes are consumed for the varint. For example, for a 4 byte
// varint, if 4 bytes are consumed that is 0b100, thus requiring clog2(4)
// +1 bits.
parameter int VARINT_LENGTH_BITS = $clog2(VARINT_NUM_BYTES)+1;
parameter int ID_BITS = 19;
// Theoretically, a page could have more than 1Mi values inside. The
// dictionary is usually capped around 1MiB, limiting the number of unique
// values, but that does not matter. Consider a page where the dioctionary has
// just one value, but the data page contains a single RLE encoding. The RLE
// count could easily be 2 million.
// While theoretically thus there's no bound for number of values, and we
// should use 32 or 64 bits, realistically all writer implemenations cap the
// number of values in a row to 1Mi, so the number of values in a page will be
// that in the worse case. Thus, 20 bits are enough.
parameter int VALUES_BITS = 20;
parameter int BPE_MASK_SIZE = ID_BITS;

// We want to have 1MiB dictionaries. That would take 20 bits to index fully.
// Since the TypedDictionary uses 32bit elements (4 bytes), we take 2 bits of (log2(4)).
typedef logic [ID_BITS - 1:0] id_t;

typedef enum logic {
    COMPRESSION_RAW = 0,
    COMPRESSION_SNAPPY = 1
} compression_t;

// Number of bits in RLE/BPE encodings
// "the bit width used to encode the entry ids stored as 1 byte (max bit width = 32)"
// This is what the specification says. In pratice, this design only supports
// ~2MiB dictionary pages, so the bit width won't be greater than 19 bits
// (which are needed to index all values at the 32bit level over 2MiB).
// In practice this is enough to support any realistic real-world parquet file,
// which tend to stick to slighly over 1MiB.
typedef logic [ID_BITS - 1:0] bit_width_t; 

// Here we're using one extra bit to handle the case where we have exactly 1Mi
// values, which can happen for RLE series, but not for BPE series.
typedef logic [VALUES_BITS:0] rle_count_t;

typedef logic [VALUES_BITS - 1:0] bpe_count_t;

typedef struct packed {
  bit_width_t bit_width;
  logic [BPE_MASK_SIZE - 1:0] mask;
  bpe_count_t count;
} bpe_config_t;

// Offset into the 64-byte input databeat
// NOTE: This is intentionally one extra bit than what would be necessary to
// allow safe indexing into double width input buffers.
typedef logic [$clog2(AXI_DATA_BITS / 8):0] offset_t;

typedef struct packed {
    bit_width_t bit_width;
    offset_t offset;
    data32_t num_values;
} run_decoder_config_t;

typedef struct packed {
    logic [VARINT_NUM_BITS - 1:0] value;
    logic [VARINT_LENGTH_BITS - 1:0] length;
} varint_t;

typedef enum logic [1:0] {
    PAGE_TYPE_HYBRID = 0,
    PAGE_TYPE_DICT = 1,
    PAGE_TYPE_PLAIN = 2
} page_type_t;

typedef struct packed {
    compression_t compression;
    data32_t      num_values;
    type_t        typ;
} column_chunk_conf_t;

typedef struct packed {
    page_type_t page_type;
    data32_t    num_values;
    logic       last;
} page_conf_t;

parameter longint unsigned PARCORE_SYSTEM_ID = 64'hfd888c49aec6e141;

parameter longint unsigned COLUMN_CHUNK_DECODER_CONFIG_REGS = 3;
parameter longint unsigned COLUMN_CHUNK_DECODER_CONFIG_ID = 64'h5c19f934407065bd;

parameter longint unsigned PAGE_DECODER_CONFIG_REGS = 3;
parameter longint unsigned PAGE_DECODER_CONFIG_ID = 64'hc0779792c320630e;

endpackage
