`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_branch;

    localparam integer DATA_W = `EG2C_DATA_W;
    localparam integer CASE_COUNT = 3;
    localparam integer OUT_COUNT = 8;

    reg signed [DATA_W-1:0] score;
    reg signed [DATA_W-1:0] threshold;
    reg [OUT_COUNT*DATA_W-1:0] coarse_vec;
    reg [OUT_COUNT*DATA_W-1:0] precise_vec;
    wire precise_en;
    wire [OUT_COUNT*DATA_W-1:0] selected_vec;

    reg [DATA_W-1:0] score_mem [0:CASE_COUNT-1];
    reg [DATA_W-1:0] threshold_mem [0:CASE_COUNT-1];
    reg [DATA_W-1:0] coarse_mem [0:CASE_COUNT*OUT_COUNT-1];
    reg [DATA_W-1:0] precise_mem [0:CASE_COUNT*OUT_COUNT-1];
    reg [DATA_W-1:0] expected_mem [0:CASE_COUNT*OUT_COUNT-1];
    reg expected_path_mem [0:CASE_COUNT-1];

    integer case_idx;
    integer elem_idx;
    integer mismatches;
    reg [DATA_W-1:0] got;
    reg [DATA_W-1:0] expected;

    eg2c_detector_branch #(
        .OUT_COUNT(OUT_COUNT)
    ) dut (
        .score_i(score),
        .threshold_i(threshold),
        .coarse_act_i(coarse_vec),
        .precise_act_i(precise_vec),
        .precise_en_o(precise_en),
        .selected_act_o(selected_vec)
    );

    initial begin
        mismatches = 0;
        score = '0;
        threshold = '0;
        coarse_vec = '0;
        precise_vec = '0;

        $readmemh("sim/build/branch/scores.hex", score_mem);
        $readmemh("sim/build/branch/thresholds.hex", threshold_mem);
        $readmemh("sim/build/branch/coarse.hex", coarse_mem);
        $readmemh("sim/build/branch/precise.hex", precise_mem);
        $readmemh("sim/build/branch/expected.hex", expected_mem);
        $readmemb("sim/build/branch/expected_path.bin", expected_path_mem);

        for (case_idx = 0; case_idx < CASE_COUNT; case_idx = case_idx + 1) begin
            score = score_mem[case_idx];
            threshold = threshold_mem[case_idx];

            for (elem_idx = 0; elem_idx < OUT_COUNT; elem_idx = elem_idx + 1) begin
                coarse_vec[elem_idx*DATA_W +: DATA_W] = coarse_mem[case_idx*OUT_COUNT + elem_idx];
                precise_vec[elem_idx*DATA_W +: DATA_W] = precise_mem[case_idx*OUT_COUNT + elem_idx];
            end

            #1;

            if (precise_en !== expected_path_mem[case_idx]) begin
                $display("ERROR: case %0d path got=%0b expected=%0b", case_idx, precise_en, expected_path_mem[case_idx]);
                mismatches = mismatches + 1;
            end

            for (elem_idx = 0; elem_idx < OUT_COUNT; elem_idx = elem_idx + 1) begin
                got = selected_vec[elem_idx*DATA_W +: DATA_W];
                expected = expected_mem[case_idx*OUT_COUNT + elem_idx];
                if (got !== expected) begin
                    $display("ERROR: case %0d output[%0d] got=%02x expected=%02x", case_idx, elem_idx, got, expected);
                    mismatches = mismatches + 1;
                end
            end
        end

        if (mismatches == 0) begin
            $display("target=branch mismatches=0 PASS cases=%0d", CASE_COUNT);
            $finish;
        end else begin
            $display("target=branch mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

endmodule

`default_nettype wire
