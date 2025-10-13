`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;

module varint3_extractor_with_field_types #(
  parameter int WIDTH_0 = 32,  // Set to 32 or 64
  parameter int WIDTH_1 = 32,  // Set to 32 or 64
  parameter int WIDTH_2 = 32  // Set to 32 or 64
) (
  input  logic [AXI_DATA_BITS-1:0] data_bus,
  output logic         [7:0] field_type_0,
  output logic signed [WIDTH_0-1:0] value_0,        // PageType
  output logic         [7:0] field_type_1,
  output logic signed [WIDTH_1-1:0] value_1,
  output logic         [7:0] field_type_2,
  output logic signed [WIDTH_2-1:0] value_2,
  output logic         [7:0] field_type_3,
  output logic               field_set_3,
  output logic signed [WIDTH_2-1:0] value_3,
  output logic         [7:0] field_type_4,
  output logic         [7:0] field_type_5,
  output logic signed [WIDTH_2-1:0] value_4,
  output logic         [7:0] field_type_6,
  output logic signed [WIDTH_2-1:0] value_5,
  output logic [3:0] length_0,
  output logic [3:0] length_1,
  output logic [3:0] length_2,
  output logic [3:0] length_3,
  output logic [3:0] length_4,
  output logic [3:0] length_5,
  output logic               parse_valid
);

  // Unpack 512-bit input into 64 bytes
  logic [7:0] bytes[0:63];
  genvar i;
  generate
    for (i = 0; i < AXI_DATA_BITS / 8; i++) begin
      assign bytes[i] = data_bus[i*8 +: 8];
    end
  endgenerate

  // Define slices for each varint
  logic [7:0] b_ptype[0:9], b_uncomp_size[0:9], b_comp_size[0:9], b_crc_optional[0:9], b_num_vals[0:9], b_encoding[0:9];

  assign field_type_0 = bytes[0];
  always_comb begin
    for (int j = 0; j < 10; j++) begin
      b_ptype[j] = bytes[j + 1]; // Offset 1 for first fieldtype byte
    end
  end
  varint_length_detector len0 (.bytes_in(b_ptype), .length(length_0));
  varint_decoder         #(.WIDTH(WIDTH_0)) dec0 (.bytes_in(b_ptype), .length(length_0), .value(value_0));


  logic [5:0] offset_uncomp_size;
  assign offset_uncomp_size = 1 + length_0;
  assign field_type_1 = bytes[offset_uncomp_size];
  always_comb begin
    for (int j = 0; j < 10; j++) begin
      b_uncomp_size[j] = bytes[offset_uncomp_size + 1 + j];
    end
  end
  varint_length_detector len1 (.bytes_in(b_uncomp_size), .length(length_1));
  varint_decoder         #(.WIDTH(WIDTH_1)) dec1 (.bytes_in(b_uncomp_size), .length(length_1), .value(value_1));


  logic [5:0] offset_comp_size;
  assign offset_comp_size = offset_uncomp_size + 1 + length_1;
  assign field_type_2 = bytes[offset_comp_size];
  always_comb begin
    for (int j = 0; j < 10; j++) begin
      b_comp_size[j] = bytes[offset_comp_size + 1 + j];
    end
  end
  varint_length_detector len2 (.bytes_in(b_comp_size), .length(length_2));
  varint_decoder         #(.WIDTH(WIDTH_2)) dec2 (.bytes_in(b_comp_size), .length(length_2), .value(value_2));


  logic [5:0] offset_crc;
  assign offset_crc = offset_comp_size + 1 + length_2;
  assign field_type_3 = bytes[offset_crc];
  assign field_set_3 = (field_type_3[3:0] == 'd5);
  always_comb begin
    for (int j = 0; j < 10; j++) begin
      b_crc_optional[j] = bytes[offset_crc + 1 + j];
    end
  end
  varint_length_detector len3 (.bytes_in(b_crc_optional), .length(length_3));
  varint_decoder         #(.WIDTH(WIDTH_2)) dec3 (.bytes_in(b_crc_optional), .length(length_3), .value(value_3));


  logic [5:0] offset_num_vals;
  always_comb begin
    if (field_set_3)
      offset_num_vals = offset_crc + 1 + length_3;
    else
      offset_num_vals = offset_crc;

    field_type_4 = bytes[offset_num_vals];
    field_type_5 = bytes[offset_num_vals + 1];
    for (int j = 0; j < 10; j++) begin
      b_num_vals[j] = bytes[offset_num_vals + 2 + j]; 
    end
  end
  varint_length_detector len4 (.bytes_in(b_num_vals), .length(length_4));
  varint_decoder         #(.WIDTH(WIDTH_2)) dec4 (.bytes_in(b_num_vals), .length(length_4), .value(value_4));


  // Only works with Data and Dictionary page headers. DataV2 has more fields!
  logic [5:0] offset_encoding;
  assign offset_encoding = offset_num_vals + 2 + length_4;
  assign field_type_6 = bytes[offset_encoding];
  always_comb begin
    for (int j = 0; j < 10; j++) begin
      b_encoding[j] = bytes[offset_encoding + 1 + j]; 
    end
  end
  varint_length_detector len5 (.bytes_in(b_encoding), .length(length_5));
  varint_decoder         #(.WIDTH(WIDTH_2)) dec5 (.bytes_in(b_encoding), .length(length_5), .value(value_5));

  assign parse_valid = (field_type_0[3:0] == 'd5 && field_type_1[3:0] == 'd5 && field_type_2[3:0] == 'd5 && field_type_4[3:0] == 'hc && field_type_5[3:0] == 'd5 && field_type_6[3:0] == 'd5);


endmodule
