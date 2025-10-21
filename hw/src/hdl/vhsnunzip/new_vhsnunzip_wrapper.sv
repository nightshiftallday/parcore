import lynxTypes::*;

module new_vhsnunzip_wrapper (
    input logic clk,
    input logic rst_n,

    AXI4S.s in,
    AXI4S.m out
);
    // Decompressor parameters
    localparam DECOMP_DATA_BITS = 64;
    localparam DECOMP_IN_CNT_BITS = 3;
    localparam DECOMP_OUT_CNT_BITS = 4;

    localparam AXI_CNT_BITS = $clog2(AXI_DATA_BITS/8);
    localparam INDEX_BITS = $clog2(AXI_DATA_BITS / DECOMP_DATA_BITS);



    // Decompressor input ports
    logic co_valid;   
    logic co_ready;
    logic [DECOMP_DATA_BITS-1:0] co_data;
    logic [DECOMP_IN_CNT_BITS-1:0] co_cnt;
    logic co_last;

    // Index in the input chunk
    logic [INDEX_BITS-1:0] in_index;
    // Was the data in the input buffers 'in_*' already processed?
    logic in_done;
    // Number of valid bytes in 'in_data' with implicit MSB
    logic [AXI_CNT_BITS-1:0] in_cnt;

    // Buffers for AXI data
    logic [AXI_DATA_BITS-1:0] in_data;
    logic [AXI_DATA_BITS/8-1:0] in_keep;
    logic in_last;

    // Decompressor output ports
    logic de_valid;
    logic de_ready;
    logic de_dvalid;
    logic [DECOMP_DATA_BITS-1:0] de_data;
    logic [DECOMP_OUT_CNT_BITS-1:0] de_cnt;
    logic de_last;

    // Index in the output chunk
    logic [INDEX_BITS-1:0] out_index;



    // Ready to receive new input when we are done with the chunk or currently streaming the last part of it.
    // assign in.tready = rst_n && (in_done || (in_index == {(INDEX_BITS){1'b1}} && co_ready));
    always_comb begin
        in.tready = 1'b0;
        if (rst_n) begin
            if (in_done) begin
                in.tready = 1'b1;
            end else if (in_index == {(INDEX_BITS){1'b1}} && co_ready) begin
                in.tready = 1'b1;
            end
        end
    end

    // in_index and in_done
    always_ff @(posedge clk) begin
	    if (rst_n) begin
            if (in.tready) begin
                if (in.tvalid) begin
                    // Read input chunk
                    in_data <= in.tdata;
                    in_keep <= in.tkeep;
                    in_last <= in.tlast;

                    in_index <= 0;
                    in_done <= 1'b0;
                end else begin
                    // Stop supplying data if there is no new input
                    in_done <= 1'b1;
                end
            end else if (co_ready && co_valid) begin
                if (co_last) begin
                    // Internal reset
                    in_index <= 0;
                    in_done <= 1'b1;
                end else begin
                    in_index <= in_index + 1;
                end
            end
    	end else begin
  	        in_index <= 0;
            in_done <= 1'b1;
        end
    end

    // in_cnt
    always_comb begin
        in_cnt = 0;
        for (int i = 0, done = 0; i < AXI_DATA_BITS/8; i++) begin
            if (!done && !in_keep[i]) begin
                in_cnt = i;
                done = 1;
            end
        end
    end

    // co_data, co_cnt, co_last and co_valid
    always_comb begin
        co_data = in_data[in_index*DECOMP_DATA_BITS+:DECOMP_DATA_BITS];

        co_cnt = 0;
        co_last = 1'b0;
        if (0 < in_cnt && in_cnt <= (in_index + 1) * DECOMP_DATA_BITS/8) begin
            // Section fed to the decompressor is only partially valid
            co_cnt = in_cnt[DECOMP_IN_CNT_BITS-1:0];
            co_last = 1'b1;
        end else if (in_last && in_index == {INDEX_BITS{1'b1}}) begin
            // Input is last chunk and index is at the end
            co_last = 1'b1;
        end

        co_valid = rst_n && !in_done;
    end
    
    // We can accept new decompressed data if the buffer 'out.tdata' is not full yet
    // or if we are in an output handshake and the buffer will be empty next cycle.
    // assign de_ready = rst_n && (!out.tvalid || out.tready);
    always_comb begin
        de_ready = 1'b0;
        if (rst_n) begin
            if (!out.tvalid) begin
                de_ready = 1'b1;
            end else if (out.tready) begin
                de_ready = 1'b1;
            end
        end
    end

    // out_index
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (de_ready && de_valid) begin
                if (de_last) begin
                    // Internal reset
                    out_index <= 0;
                end else begin
                    out_index <= out_index + 1;
                end
            end 
        end else begin
            out_index <= 0;
        end
    end

    // out.tdata, out.tkeep and out.tlast
    always_ff @(posedge clk) begin
        logic [AXI_DATA_BITS/8-1:0] tmp_keep;
        if (rst_n) begin
            if (de_ready && de_valid) begin
                // Read decompressed data
                out.tdata[out_index*DECOMP_DATA_BITS+:DECOMP_DATA_BITS] <= de_data;
                out.tlast <= de_last;
            end

            tmp_keep = out.tkeep;
            if (out.tready && out.tvalid) begin
                // Reset keep signal on output handshake.
                tmp_keep = 0;
            end
            if (de_ready && de_valid) begin
                // Compute keep signal for read data.
                tmp_keep[out_index*DECOMP_DATA_BITS/8+:DECOMP_DATA_BITS/8] =
                    de_dvalid
                        ? (de_cnt == 0 
                            ? {(DECOMP_DATA_BITS/8){1'b1}}
                            : (1 << de_cnt) - 1)
                        : 0;
            end
            out.tkeep <= tmp_keep;
        end
    end

    // out.tvalid
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (de_ready && de_valid && (out_index == {INDEX_BITS{1'b1}} || de_last)) begin
                // We are ready to transmit the next chunk after the final (for the chunk or in total) bit was read.
                out.tvalid <= 1'b1;
            end else if (out.tvalid && out.tready) begin
                // Reset after handshake.
                out.tvalid <= 1'b0;
            end
        end else begin
            out.tvalid <= 1'b0;
        end
    end

    vhsnunzip_unbuffered #(
        .LONG_CHUNKS(1),
        .RAM_STYLE("ultra")
    ) decompressor (
        .clk(clk),
        .reset(~rst_n),

        .co_valid(co_valid),
        .co_ready(co_ready),
        .co_data(co_data),
        .co_cnt(co_cnt),
        .co_last(co_last),

        .de_valid(de_valid),
        .de_ready(de_ready),
        .de_dvalid(de_dvalid),
        .de_data(de_data),
        .de_cnt(de_cnt),
        .de_last(de_last)
    );
endmodule
