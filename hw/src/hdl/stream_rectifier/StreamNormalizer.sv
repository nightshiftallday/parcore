`timescale 1ns / 1ps

`include "axi_macros.svh"

import lynxTypes::*;

module StreamNormalizer #(
    parameter WIDTH = 512,
    parameter CELL_WIDTH = 32,
    parameter ENABLE_COMPACTOR = 0,
    parameter COMPACTOR_REGISTER_LEVELS = 0,
    parameter BARREL_SHIFTER_REGISTER_LEVELS = 0
) (
    input logic aclk,
    input logic aresetn,

    AXI4SC.s i_data,
    AXI4SC.m o_data
);

localparam int BYTES = WIDTH / 8;

logic first_packet;
logic[$clog2(BYTES) - 1:0] offset;
logic[$clog2(BYTES) - 1:0] offset_comb;

AXI4SC axis_compactor(.aclk(aclk));
AXI4SC axis_shifted(.aclk(aclk));
AXI4SC register(.aclk(aclk));

logic emit;
logic[WIDTH / 8 - 1:0] register_and_shifted_keep;
logic[WIDTH / 8 - 1:0] register_or_shifted_keep;

generate if (ENABLE_COMPACTOR) begin
    Compactor #(.WIDTH(WIDTH), .CELL_WIDTH(CELL_WIDTH), .REGISTER_LEVELS(COMPACTOR_REGISTER_LEVELS)) inst_compactor (
        .aclk(aclk),
        .aresetn(aresetn),

        .i_data(i_data),
        .o_data(axis_compactor)
    );
end else begin
    `AXIS_ASSIGN(i_data, axis_compactor);
end endgenerate

always_ff @(posedge aclk) begin
    if (~aresetn) begin
        first_packet <= 1;
        offset <= 0;
    end else if (axis_compactor.tvalid && axis_compactor.tready) begin
        if (axis_compactor.tlast) begin
            first_packet <= 1;
        end else if (first_packet && |axis_compactor.tkeep) begin
            first_packet <= 0;
        end
    end
end
assign offset_comb = (first_packet) ? (offset + $countones(axis_compactor.tkeep)) : (offset + $countones(register.tkeep));

BarrelShifter #(.WIDTH(WIDTH), .REGISTER_LEVELS(BARREL_SHIFTER_REGISTER_LEVELS)) inst_shifter ( // TODO Implement CELL_WIDTH for BarrelShifter to reduce complexity
    .aclk(aclk),
    .aresetn(aresetn),

    .i_offset(offset_comb ),
    .i_data(axis_compactor),
    .o_data(axis_shifted)
);

always_ff @(posedge aclk) begin
    if (~aresetn) begin
        register.tvalid <= 0;
        register.tlast <= 0;
        register.tkeep <= '0;
        o_data.tvalid   <= 0;
        o_data.tlast   <= 0;
    end else begin
        if (o_data.tready) begin // TODO Add to condition: or !o_data.tvalid or new data does not overflow register (but then o_data needs to be handled differently too)
            for (int i = 0; i < BYTES; i++) begin
                if (register.tvalid && register.tkeep[i]) begin
                    o_data.tdata[i * 8+:8] <= register.tdata[i * 8+:8];
                    if (emit) begin
                        register.tdata[i * 8+:8] <= axis_shifted.tdata[i * 8+:8];
                    end
                end else begin
                    o_data.tdata[i * 8+:8]   <= axis_shifted.tdata[i * 8+:8];
                    register.tdata[i * 8+:8] <= axis_shifted.tdata[i * 8+:8];
                end
            end

            if (axis_shifted.tvalid) begin // Only if valid data is coming out of the shifter, the output stage can be updated
                if (emit) begin // The output register would be full
                    o_data.tkeep  <= -1;
                    o_data.tvalid <= 1;

                    if (axis_shifted.tlast) begin // Handle tlast
                        if (register_and_shifted_keep == 0) begin // All remaining data leaves this cycle, so this is last anyway
                            o_data.tlast <= 1;
                        end else begin // Set flag so that next cycle will write output register
                            register.tlast <= 1;
                        end
                    end else begin
                        register.tlast <= 0;
                        o_data.tlast   <= 0;
                    end

                    register.tkeep  <= register_and_shifted_keep;
                    register.tvalid <= |register_and_shifted_keep;
                end else begin
                    if (axis_shifted.tlast) begin // If this is the last transfer, transmit output register and pipeline output directly
                        o_data.tkeep  <= register_or_shifted_keep;
                        o_data.tlast  <= 1;
                        o_data.tvalid <= 1;

                        register.tvalid <= 0;
                    end else begin
                        o_data.tvalid <= 0; // this cannot be valid anymore
                        
                        register.tkeep  <= register_or_shifted_keep;
                        register.tlast  <= 0;
                        register.tvalid <= |register_or_shifted_keep;
                    end
                end
            end else begin
                if (register.tvalid && (&register.tkeep || register.tlast)) begin
                    o_data.tkeep  <= register.tkeep;
                    o_data.tlast  <= register.tlast;
                    o_data.tvalid <= 1;

                    register.tlast  <= 0;
                    register.tvalid <= 0;
                end else begin
                    o_data.tvalid <= 0;
                    o_data.tlast <= 0;
                end
            end
        end
    end
end

assign emit = register.tvalid && &(register.tkeep | axis_shifted.tkeep);
assign register_and_shifted_keep = register.tvalid ? register.tkeep & axis_shifted.tkeep : axis_shifted.tkeep;
assign register_or_shifted_keep = register.tvalid ? register.tkeep | axis_shifted.tkeep : axis_shifted.tkeep;

assign axis_shifted.tready = o_data.tready;

endmodule
