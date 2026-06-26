`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_dw_reuse;

    localparam integer IN_H = 4;
    localparam integer IN_W = 4;
    localparam integer CHANNELS = 4;
    localparam integer K_H = 3;
    localparam integer K_W = 3;
    localparam integer DATA_W = `EG2C_DATA_W;
    localparam integer WEIGHT_W = `EG2C_WEIGHT_W;

    localparam integer INPUT_COUNT = IN_H * IN_W * CHANNELS;
    localparam integer WEIGHT_COUNT = K_H * K_W * CHANNELS;
    localparam integer OUTPUT_COUNT = IN_H * IN_W * CHANNELS;

    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;
    wire [31:0] simple_cycles;
    wire [31:0] cir_cycles;
    wire [31:0] drir_cycles;
    wire [OUTPUT_COUNT*DATA_W-1:0] output_flat;

    reg [DATA_W-1:0] input_mem [0:INPUT_COUNT-1];
    reg [WEIGHT_W-1:0] weight_mem [0:WEIGHT_COUNT-1];
    reg [DATA_W-1:0] expected_mem [0:OUTPUT_COUNT-1];
    reg [31:0] expected_stats [0:2];
    reg [INPUT_COUNT*DATA_W-1:0] input_flat;
    reg [WEIGHT_COUNT*WEIGHT_W-1:0] weight_flat;

    integer idx;
    integer mismatches;
    integer cycles_waited;
    reg [DATA_W-1:0] got;
    reg [DATA_W-1:0] expected;

    eg2c_dw_reuse_conv2d #(
        .IN_H(IN_H),
        .IN_W(IN_W),
        .CHANNELS(CHANNELS),
        .K_H(K_H),
        .K_W(K_W),
        .PAD_H(1),
        .PAD_W(1)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .input_act_i(input_flat),
        .weight_i(weight_flat),
        .output_act_o(output_flat),
        .busy_o(busy),
        .done_o(done),
        .simple_cycle_count_o(simple_cycles),
        .cir_cycle_count_o(cir_cycles),
        .drir_cycle_count_o(drir_cycles)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/dw_reuse/wave.vcd");
            $dumpvars(0, tb_dw_reuse);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        input_flat = '0;
        weight_flat = '0;

        $readmemh("sim/build/dw_reuse/input_act.hex", input_mem);
        $readmemh("sim/build/dw_reuse/weights.hex", weight_mem);
        $readmemh("sim/build/dw_reuse/expected.hex", expected_mem);
        $readmemh("sim/build/dw_reuse/expected_stats.hex", expected_stats);

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

        for (idx = 0; idx < 3; idx = idx + 1) begin
            if (^expected_stats[idx] === 1'bx) begin
                $display("ERROR: expected_stats[%0d] has X/Z after load", idx);
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
            $display("ERROR: dw_reuse did not assert done within timeout");
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

        if (simple_cycles !== expected_stats[0]) begin
            $display("ERROR: simple_cycles got=%0d expected=%0d", simple_cycles, expected_stats[0]);
            mismatches = mismatches + 1;
        end

        if (cir_cycles !== expected_stats[1]) begin
            $display("ERROR: cir_cycles got=%0d expected=%0d", cir_cycles, expected_stats[1]);
            mismatches = mismatches + 1;
        end

        if (drir_cycles !== expected_stats[2]) begin
            $display("ERROR: drir_cycles got=%0d expected=%0d", drir_cycles, expected_stats[2]);
            mismatches = mismatches + 1;
        end

        if (!(cir_cycles < simple_cycles && drir_cycles < simple_cycles)) begin
            $display("ERROR: reuse counters did not improve over simple schedule");
            mismatches = mismatches + 1;
        end

        if (mismatches == 0) begin
            $display("target=dw_reuse mismatches=0 PASS simple=%0d cir=%0d drir=%0d",
                     simple_cycles, cir_cycles, drir_cycles);
            $finish;
        end else begin
            $display("target=dw_reuse mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

endmodule

`default_nettype wire
