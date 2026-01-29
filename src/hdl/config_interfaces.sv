`timescale 1ns / 1ps

`include "libstf_macros.svh"

import parcore::compression_t;
import libstf::data32_t;
import libstf::type_t;

/**
 * Interface that bundles all configuration needed to decode a parquet page.
 */
interface page_decoder_config_i (
    input logic clk,
    input logic rst_n
);
    compression_t compression;
    page_type_t   page_type;
    data32_t      num_values;
    type_t        typ;
    logic         valid;
    logic         ready;

    modport m (
        output compression, page_type, num_values, typ, valid,
        input ready
    );

    modport s (
        output ready,
        input compression, page_type, num_values, typ, valid
    );

`ifndef SYNTHESIS
    `STF_ASSERT_STABLE(compression, valid, ready);
    `STF_ASSERT_STABLE(page_type, valid, ready);
    `STF_ASSERT_STABLE(num_values, valid, ready);
    `STF_ASSERT_STABLE(typ, valid, ready);
    `STF_ASSERT_NOT_UNDEFINED(valid);
    `STF_ASSERT_NOT_UNDEFINED(ready);
`endif
endinterface

/**
 * Interface that bundles all configuration needed to decode a hybrid encoding
 * sequence.
 */
interface hybrid_page_decoder_config_i (
    input logic clk,
    input logic rst_n
);
    data32_t      num_values;
    logic         valid;
    logic         ready;

    modport m (
        output num_values, valid,
        input ready
    );

    modport s (
        output ready,
        input num_values, valid
    );

`ifndef SYNTHESIS
    `STF_ASSERT_STABLE(num_values, valid, ready);
    `STF_ASSERT_NOT_UNDEFINED(valid);
    `STF_ASSERT_NOT_UNDEFINED(ready);
`endif
endinterface
