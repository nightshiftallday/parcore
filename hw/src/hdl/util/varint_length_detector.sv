`timescale 1ns / 1ps

module varint_length_detector (
  input  logic [7:0] bytes_in[0:9],
  output logic [3:0] length
);
  always_comb begin
    length = 10; // default to max
    for (int i = 0; i < 10; i++) begin
      if (bytes_in[i][7] == 1'b0) begin
        length = i + 1;
        break;
      end
    end
  end
endmodule
