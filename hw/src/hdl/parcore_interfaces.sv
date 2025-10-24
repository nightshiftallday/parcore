interface bitdata_i #(
    parameter NUM_BITS,
    parameter type meta_t
);
    logic[NUM_BITS - 1:0] data;
    meta_t                meta;
    logic                 valid;
    logic                 ready;

    modport m (
        input  ready,
        output data, meta, valid
    );

    modport s (
        input  data, meta, valid,
        output ready
    );

    task tie_off_m(); // Tie off unused master signals
        ready = 1'b0;
    endtask

    task tie_off_s(); // Tie off unused slave signals
        valid = 1'b0;
    endtask
endinterface

module BitdataCyclicDriver #(
    parameter NUM_BITS,
    parameter type meta_t,
    parameter NUM_ELEMENTS
) (
    input logic clk,
    input logic rst_n,

    input logic[NUM_BITS - 1:0] data[NUM_ELEMENTS - 1:0],
    input meta_t meta[NUM_ELEMENTS - 1:0],

    bitdata_i.m out_data // #(NUM_BITS, meta_t)
);

reg [$clog2(NUM_ELEMENTS)-1:0] i;

// We always have data to put out, as we're cycling through the input values
assign out_data.valid = rst_n;
assign out_data.data = data[i];
assign out_data.meta = meta[i];

always_ff @(posedge clk) begin
    if (rst_n == 1'b0) begin
        i <= 0;
    end else if (out_data.ready) begin
        i <= (i + 1) % NUM_ELEMENTS;
    end
end

endmodule
