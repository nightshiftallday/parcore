`ifndef _PARCORE_PARCORE_TYPES_H_
`define _PARCORE_PARCORE_TYPES_H_

`include "lynx_macros.svh"

package parcore;

import libstf::data32_t;
import libstf::data64_t;
import libstf::type_t;
import lynxTypes::*;

parameter int VARINT_NUM_BYTES = 4;
parameter int VARINT_NUM_BITS = VARINT_NUM_BYTES * 7;
parameter int VARINT_LENGTH_BITS = $clog2(VARINT_NUM_BYTES);
parameter int BPE_MASK_SIZE = 18;

// We want to have 1MiB dictionaries. That would take 20 bits to index fully.
// Since the TypedDictionary uses 32bit elements (4 bytes), we take 2 bits of (log2(4)).
typedef logic [BPE_MASK_SIZE - 1:0] id_t;

typedef enum logic {
    COMPRESSION_RAW = 0,
    COMPRESSION_SNAPPY = 1
} compression_t;

// Number of bits in RLE/BPE encodings
// "the bit width used to encode the entry ids stored as 1 byte (max bit width = 32)"
// NOTE: This does not allow bit-width of 32!!
// This is a limitation of the design. Nevertheless, bit_width=32 is unlikely.
typedef logic [$clog2(32) - 1:0] bit_width_t; 

typedef data32_t rle_count_t;

typedef data32_t bpe_count_t;

typedef struct packed {
  bit_width_t bit_width;
  logic [BPE_MASK_SIZE - 1:0] mask;
  bpe_count_t count;
} bpe_metadata_t;

// Offset into the 64-byte input databeat
// NOTE: This is intentionally one extra bit than what would be necessary to
// allow safe indexing into double width input buffers.
typedef logic [$clog2(AXI_DATA_BITS / 8):0] offset_t;

typedef struct packed {
    bit_width_t bit_width;
    offset_t offset;
    data32_t num_values;
} run_decoder_metadata_t;

typedef struct packed {
    logic [VARINT_NUM_BITS - 1:0] value;
    logic [$clog2(VARINT_NUM_BYTES) - 1:0] length;
} varint_t;

typedef enum logic [1:0] {
    PAGE_TYPE_HYBRID = 0,
    PAGE_TYPE_DICT = 1,
    PAGE_TYPE_PLAIN = 2
} page_type_t;

parameter longint unsigned PARCORE_SYSTEM_ID = 64'hfd888c49aec6e141;

parameter int PAGE_DECODER_CONFIG_NUM_REGS = 4;
parameter longint unsigned PAGE_DECODER_CONFIG_ID = 64'hc0779792c320630e;

parameter int HYBRID_PAGE_DECODER_CONFIG_NUM_REGS = 2;
parameter longint unsigned HYBRID_PAGE_DECODER_CONFIG_ID = 64'hd6736a4eef933024;

endpackage

`endif
