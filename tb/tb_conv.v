`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_conv;

    localparam integer IN_H = 4;
    localparam integer IN_W = 4;
    localparam integer IN_C = 2;
    localparam integer OUT_C = 3;
    localparam integer K_H = 3;
    localparam integer K_W = 3;
    localparam integer DATA_W = `EG2C_DATA_W;
    localparam integer WEIGHT_W = `EG2C_WEIGHT_W;

    localparam integer INPUT_COUNT = IN_H * IN_W * IN_C;
    localparam integer WEIGHT_COUNT = K_H * K_W * IN_C * OUT_C;
    localparam integer OUTPUT_COUNT = IN_H * IN_W * OUT_C;
    localparam integer SPARSE_VEC_LEN = K_W * IN_C;
    localparam integer SPARSE_VEC_COUNT = (K_H * K_W * IN_C + SPARSE_VEC_LEN - 1) / SPARSE_VEC_LEN;
    localparam integer SPARSE_VALID_COUNT = OUT_C * SPARSE_VEC_COUNT;

    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;
    wire [31:0] cycle_count;
    wire [31:0] active_cycle_count;
    wire [31:0] skipped_vector_count;
    wire [OUTPUT_COUNT*DATA_W-1:0] output_flat;

    reg [DATA_W-1:0] input_mem [0:INPUT_COUNT-1];
    reg [WEIGHT_W-1:0] weight_mem [0:WEIGHT_COUNT-1];
    reg [DATA_W-1:0] expected_mem [0:OUTPUT_COUNT-1];
    reg [INPUT_COUNT*DATA_W-1:0] input_flat;
    reg [WEIGHT_COUNT*WEIGHT_W-1:0] weight_flat;

    integer idx;
    integer mismatches;
    integer cycles_waited;
    reg [DATA_W-1:0] got;
    reg [DATA_W-1:0] expected;

    eg2c_dense_conv2d #(
        .IN_H(IN_H),
        .IN_W(IN_W),
        .IN_C(IN_C),
        .OUT_C(OUT_C),
        .K_H(K_H),
        .K_W(K_W),
        .PAD_H(1),
        .PAD_W(1)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .sparse_enable_i(1'b0),
        .input_act_i(input_flat),
        .weight_i(weight_flat),
        .sparse_vector_valid_i({SPARSE_VALID_COUNT{1'b0}}),
        .output_act_o(output_flat),
        .busy_o(busy),
        .done_o(done),
        .cycle_count_o(cycle_count),
        .active_cycle_count_o(active_cycle_count),
        .skipped_vector_count_o(skipped_vector_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/conv/wave.vcd");
            $dumpvars(0, tb_conv);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        input_flat = '0;
        weight_flat = '0;

        $readmemh("sim/build/conv/input_act.hex", input_mem);
        $readmemh("sim/build/conv/weights.hex", weight_mem);
        $readmemh("sim/build/conv/expected.hex", expected_mem);

        for (idx = 0; idx < INPUT_COUNT; idx = idx + 1) begin
            if (^input_mem[idx] === 1'bx) begin
                $display("ERROR: input_act[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < WEIGHT_COUNT; idx = idx + 1) begin
            if (^weight_mem[idx] === 1'bx) begin
                $display("ERROR: weights[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
            if (^expected_mem[idx] === 1'bx) begin
                $display("ERROR: expected[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < INPUT_COUNT; idx = idx + 1) begin
            input_flat[idx*DATA_W +: DATA_W] = input_mem[idx];
        end

        for (idx = 0; idx < WEIGHT_COUNT; idx = idx + 1) begin
            weight_flat[idx*WEIGHT_W +: WEIGHT_W] = weight_mem[idx];
        end

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        cycles_waited = 0;
        while (!done && cycles_waited < 2000) begin
            @(posedge clk);
            #1;
            cycles_waited = cycles_waited + 1;
        end

        if (!done) begin
            $display("ERROR: conv did not assert done within timeout");
            mismatches = mismatches + 1;
        end

        for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
            got = output_flat[idx*DATA_W +: DATA_W];
            expected = expected_mem[idx];
            if (got !== expected) begin
                $display("ERROR: output[%0d] got=%02x expected=%02x", idx, got, expected);
                mismatches = mismatches + 1;
            end
        end

        if (cycle_count !== 32'd864) begin
            $display("ERROR: cycle_count got=%0d expected=864", cycle_count);
            mismatches = mismatches + 1;
        end

        if (active_cycle_count !== cycle_count) begin
            $display("ERROR: active_cycle_count got=%0d expected=%0d in dense mode", active_cycle_count, cycle_count);
            mismatches = mismatches + 1;
        end

        if (skipped_vector_count !== 32'd0) begin
            $display("ERROR: skipped_vector_count got=%0d expected=0 in dense mode", skipped_vector_count);
            mismatches = mismatches + 1;
        end

        if (mismatches == 0) begin
            $display("target=conv mismatches=0 PASS cycles=%0d", cycle_count);
            $finish;
        end else begin
            $display("target=conv mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

endmodule

`default_nettype wire
