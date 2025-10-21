`ifndef _PARCORE_PARCORE_TYPES_H_
`define _PARCORE_PARCORE_TYPES_H_

package parcore;

typedef enum logic {
  COMPRESSION_RAW,
  COMPRESSION_SNAPPY
} compression_t;

typedef struct {
	compression_t compression;
} page_metadata_t;

endpackage

`endif
