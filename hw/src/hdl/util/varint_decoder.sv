`timescale 1ns / 1ps

module varint_decoder #(
  parameter int WIDTH = 64  // Set to 32 or 64
) (
  input  logic [7:0] bytes_in[0:9],
  input  logic [3:0] length,
  output logic signed [WIDTH-1:0] value
);
  logic [6:0] data [0:9];
  logic [WIDTH-1:0] raw;

  always_comb begin
    raw = '0;
    for (int i = 0; i < 10; i++) begin
      data[i] = bytes_in[i][6:0];
      if (i < length)
        raw |= {WIDTH{1'b0}} | (data[i] << (i * 7));
    end
  end

  assign value = $signed((raw >> 1) ^ -$signed(raw[0]));
endmodule
