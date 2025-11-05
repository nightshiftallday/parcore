`ifndef _PARCORE_PARCORE_TYPES_H_
`define _PARCORE_PARCORE_TYPES_H_

package parcore;

import libstf::data32_t;

parameter integer AXI_DATA_BITS = 512;
parameter int VARINT_NUM_BYTES = 4;
parameter int VARINT_NUM_BITS = VARINT_NUM_BYTES * 8;

typedef enum logic {
    COMPRESSION_RAW,
    COMPRESSION_SNAPPY
} compression_t;

typedef struct packed {
    compression_t compression;
    data32_t num_values;
} page_metadata_t;

// Number of bits in RLE/BPE encodings
typedef logic [3:0] bit_width_t;

typedef data32_t rle_count_t;

typedef data32_t bpe_count_t;

typedef struct packed {
  bit_width_t bit_width;
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

endpackage

`endif
