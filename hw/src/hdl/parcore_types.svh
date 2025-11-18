`ifndef _PARCORE_PARCORE_TYPES_H_
`define _PARCORE_PARCORE_TYPES_H_

`include "lynx_macros.svh"

package parcore;

import libstf::data32_t;
import libstf::data64_t;
import libstf::type_t;
import libstf::vaddress_t;
import libstf::alloc_size_t;
import lynxTypes::*;

parameter int VARINT_NUM_BYTES = 4;
parameter int VARINT_NUM_BITS = VARINT_NUM_BYTES * 8;
parameter int VARINT_LENGTH_BITS = $clog2(VARINT_NUM_BYTES);

typedef enum logic {
    COMPRESSION_RAW,
    COMPRESSION_SNAPPY
} compression_t;

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

typedef enum logic {
    PAGE_TYPE_HYBRID,
    PAGE_TYPE_DICT
} page_type_t;

typedef struct packed {
    compression_t compression;
    data32_t num_values;
    type_t typ;
    page_type_t page_type;
} page_metadata_t;

typedef data64_t rdma_vaddress_t;
typedef data64_t rdma_alloc_size_t;

typedef struct packed {
    rdma_vaddress_t   vaddr;
    rdma_alloc_size_t size;
} rdma_buffer_t;

typedef struct packed {
    rdma_vaddress_t   in_vaddr;
    rdma_alloc_size_t in_size;

    logic [7 - $bits(compression_t):0] pad_1; // byte align compression
    compression_t compression;
    data32_t num_values;
    logic [7 - $bits(type_t):0] pad_2;        // byte align type
    type_t typ;
    logic [7 - $bits(page_type_t):0] pad_3;     // byte align page_type
    page_type_t page_type;

    vaddress_t   out_vaddr;
    alloc_size_t out_size;
    logic [$bits(alloc_size_t) % 8 - 1:0] pad_4; // byte align size

    // Round up to 64 bytes (512 bits)
    // current data size is: 8 + 8 + 1 + 4 + 1 + 1 + 6 + 4 = 33
    // thus, we need to fill 64 - 33 = 31 bytes
    logic [31 * 8 - 1:0] pad_5;
} parcore_cmd_t;

endpackage

`endif
