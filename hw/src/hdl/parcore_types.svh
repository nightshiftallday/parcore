`ifndef _PARCORE_PARCORE_TYPES_H_
`define _PARCORE_PARCORE_TYPES_H_

`include "parcore_types.svh"

package parcore;

typedef enum logic {
  COMPRESSION_RAW,
  COMPRESSION_SNAPPY
} compression_t;

typedef struct packed {
	compression_t compression;
} page_metadata_t;

typedef logic [31:0] rle_count_t;

endpackage

`endif
