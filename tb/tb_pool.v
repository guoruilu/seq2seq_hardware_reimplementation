`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_pool;

    localparam integer IN_H = 4;
    localparam integer IN_W = 4;
    localparam integer CHANNELS = 3;
    localparam integer OUT_H = 2;
    localparam integer OUT_W = 2;
    localparam integer DATA_W = `EG2C_DATA_W;

    localparam integer INPUT_COUNT = IN_H * IN_W * CHANNELS;
    localparam integer OUTPUT_COUNT = OUT_H * OUT_W * CHANNELS;

    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;
    wire [31:0] cycle_count;
    wire [OUTPUT_COUNT*DATA_W-1:0] output_flat;

    reg [DATA_W-1:0] input_mem [0:INPUT_COUNT-1];
    reg [DATA_W-1:0] expected_mem [0:OUTPUT_COUNT-1];
    reg [INPUT_COUNT*DATA_W-1:0] input_flat;

    integer idx;
    integer mismatches;
    integer cycles_waited;
    reg [DATA_W-1:0] got;
    reg [DATA_W-1:0] expected;

    eg2c_avg_pool2d #(
        .IN_H(IN_H),
        .IN_W(IN_W),
        .CHANNELS(CHANNELS),
        .POOL_H(2),
        .POOL_W(2),
        .STRIDE_H(2),
        .STRIDE_W(2),
        .OUT_H(OUT_H),
        .OUT_W(OUT_W)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .input_act_i(input_flat),
        .output_act_o(output_flat),
        .busy_o(busy),
        .done_o(done),
        .cycle_count_o(cycle_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/pool/wave.vcd");
            $dumpvars(0, tb_pool);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        input_flat = '0;

        $readmemh("sim/build/pool/input_act.hex", input_mem);
        $readmemh("sim/build/pool/expected.hex", expected_mem);

        for (idx = 0; idx < INPUT_COUNT; idx = idx + 1) begin
            input_flat[idx*DATA_W +: DATA_W] = input_mem[idx];
        end

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        cycles_waited = 0;
        while (!done && cycles_waited < 500) begin
            @(posedge clk);
            #1;
            cycles_waited = cycles_waited + 1;
        end

        if (!done) begin
            $display("ERROR: pool did not assert done within timeout");
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

        if (cycle_count !== 32'd48) begin
            $display("ERROR: cycle_count got=%0d expected=48", cycle_count);
            mismatches = mismatches + 1;
        end

        if (mismatches == 0) begin
            $display("target=pool mismatches=0 PASS cycles=%0d", cycle_count);
            $finish;
        end else begin
            $display("target=pool mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

endmodule

`default_nettype wire
