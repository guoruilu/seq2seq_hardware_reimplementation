`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_pipeline_dense;

    localparam integer IN_H = 4;
    localparam integer IN_W = 4;
    localparam integer IN_C = 2;
    localparam integer CONV_OUT_C = 3;
    localparam integer POOL_OUT_H = 2;
    localparam integer POOL_OUT_W = 2;
    localparam integer INSTR_COUNT = 4;
    localparam integer DATA_W = `EG2C_DATA_W;
    localparam integer WEIGHT_W = `EG2C_WEIGHT_W;
    localparam integer INSTR_W = `EG2C_INSTR_W;

    localparam integer INPUT_COUNT = IN_H * IN_W * IN_C;
    localparam integer WEIGHT_COUNT = 3 * 3 * IN_C * CONV_OUT_C;
    localparam integer OUTPUT_COUNT = POOL_OUT_H * POOL_OUT_W * CONV_OUT_C;

    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;
    wire error;
    wire [31:0] cycle_count;
    wire [7:0] op_count;
    wire [OUTPUT_COUNT*DATA_W-1:0] output_flat;

    reg [INSTR_W-1:0] instr_mem [0:INSTR_COUNT-1];
    reg [DATA_W-1:0] input_mem [0:INPUT_COUNT-1];
    reg [WEIGHT_W-1:0] weight_mem [0:WEIGHT_COUNT-1];
    reg [DATA_W-1:0] expected_mem [0:OUTPUT_COUNT-1];
    reg [INSTR_COUNT*INSTR_W-1:0] instr_flat;
    reg [INPUT_COUNT*DATA_W-1:0] input_flat;
    reg [WEIGHT_COUNT*WEIGHT_W-1:0] weight_flat;

    integer idx;
    integer mismatches;
    integer cycles_waited;
    reg [DATA_W-1:0] got;
    reg [DATA_W-1:0] expected;

    eg2c_dense_pipeline #(
        .INSTR_COUNT(INSTR_COUNT),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .IN_C(IN_C),
        .CONV_OUT_C(CONV_OUT_C),
        .POOL_OUT_H(POOL_OUT_H),
        .POOL_OUT_W(POOL_OUT_W)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .instr_mem_i(instr_flat),
        .input_act_i(input_flat),
        .conv_weight_i(weight_flat),
        .output_act_o(output_flat),
        .busy_o(busy),
        .done_o(done),
        .error_o(error),
        .cycle_count_o(cycle_count),
        .op_count_o(op_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/pipeline_dense/wave.vcd");
            $dumpvars(0, tb_pipeline_dense);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        instr_flat = '0;
        input_flat = '0;
        weight_flat = '0;

        $readmemh("sim/build/pipeline_dense/instr.hex", instr_mem);
        $readmemh("sim/build/pipeline_dense/input_act.hex", input_mem);
        $readmemh("sim/build/pipeline_dense/weights.hex", weight_mem);
        $readmemh("sim/build/pipeline_dense/expected.hex", expected_mem);

        for (idx = 0; idx < INSTR_COUNT; idx = idx + 1) begin
            if (^instr_mem[idx] === 1'bx) begin
                $display("ERROR: instr[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

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

        for (idx = 0; idx < INSTR_COUNT; idx = idx + 1) begin
            instr_flat[idx*INSTR_W +: INSTR_W] = instr_mem[idx];
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
            $display("ERROR: pipeline_dense did not assert done within timeout");
            mismatches = mismatches + 1;
        end

        if (error) begin
            $display("ERROR: pipeline_dense asserted error");
            mismatches = mismatches + 1;
        end

        if (op_count !== 8'd2) begin
            $display("ERROR: op_count got=%0d expected=2", op_count);
            mismatches = mismatches + 1;
        end

        if (cycle_count !== 32'd912) begin
            $display("ERROR: cycle_count got=%0d expected=912", cycle_count);
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

        if (mismatches == 0) begin
            $display("target=pipeline_dense mismatches=0 PASS cycles=%0d ops=%0d", cycle_count, op_count);
            $finish;
        end else begin
            $display("target=pipeline_dense mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

endmodule

`default_nettype wire
