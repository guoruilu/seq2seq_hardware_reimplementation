`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_sparse;

    localparam integer DATA_W = `EG2C_DATA_W;
    localparam integer WEIGHT_W = `EG2C_WEIGHT_W;
    localparam integer INDEX_W = `EG2C_INDEX_W;
    localparam integer ACT_COUNT = 16;
    localparam integer VEC_COUNT = 5;
    localparam integer VEC_LEN = 3;
    localparam integer INDEX_COUNT = VEC_COUNT * VEC_LEN;

    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;
    wire [DATA_W-1:0] output_act;
    wire signed [`EG2C_ACC_W-1:0] output_acc;
    wire [31:0] cycle_count;
    wire [31:0] active_cycle_count;
    wire [31:0] skipped_vector_count;

    reg [DATA_W-1:0] act_mem [0:ACT_COUNT-1];
    reg [INDEX_W-1:0] index_mem [0:INDEX_COUNT-1];
    reg [WEIGHT_W-1:0] weight_mem [0:INDEX_COUNT-1];
    reg valid_mem [0:VEC_COUNT-1];
    reg [31:0] expected_stats [0:4];
    reg [DATA_W-1:0] expected_mem [0:0];

    reg [ACT_COUNT*DATA_W-1:0] act_flat;
    reg [INDEX_COUNT*INDEX_W-1:0] index_flat;
    reg [INDEX_COUNT*WEIGHT_W-1:0] weight_flat;
    reg [VEC_COUNT-1:0] valid_vec;

    integer idx;
    integer mismatches;
    integer cycles_waited;

    eg2c_sparse_vector_mac #(
        .ACT_COUNT(ACT_COUNT),
        .VEC_COUNT(VEC_COUNT),
        .VEC_LEN(VEC_LEN)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .act_vec_i(act_flat),
        .index_vec_i(index_flat),
        .weight_vec_i(weight_flat),
        .vector_valid_i(valid_vec),
        .output_act_o(output_act),
        .output_acc_o(output_acc),
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
            $dumpfile("sim/build/sparse/wave.vcd");
            $dumpvars(0, tb_sparse);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        act_flat = '0;
        index_flat = '0;
        weight_flat = '0;
        valid_vec = '0;

        $readmemh("sim/build/sparse/input_act.hex", act_mem);
        $readmemh("sim/build/sparse/indices.hex", index_mem);
        $readmemh("sim/build/sparse/weights.hex", weight_mem);
        $readmemb("sim/build/sparse/vector_valid.bin", valid_mem);
        $readmemh("sim/build/sparse/expected.hex", expected_mem);
        $readmemh("sim/build/sparse/expected_stats.hex", expected_stats);

        for (idx = 0; idx < ACT_COUNT; idx = idx + 1) begin
            if (^act_mem[idx] === 1'bx) begin
                $display("ERROR: sparse input_act[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < INDEX_COUNT; idx = idx + 1) begin
            if (^index_mem[idx] === 1'bx || ^weight_mem[idx] === 1'bx) begin
                $display("ERROR: sparse index/weight[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < VEC_COUNT; idx = idx + 1) begin
            if (valid_mem[idx] !== 1'b0 && valid_mem[idx] !== 1'b1) begin
                $display("ERROR: sparse vector_valid[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        if (^expected_mem[0] === 1'bx) begin
            $display("ERROR: sparse expected output has X/Z after load");
            mismatches = mismatches + 1;
        end

        for (idx = 0; idx < 5; idx = idx + 1) begin
            if (^expected_stats[idx] === 1'bx) begin
                $display("ERROR: sparse expected_stats[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < ACT_COUNT; idx = idx + 1) begin
            act_flat[idx*DATA_W +: DATA_W] = act_mem[idx];
        end

        for (idx = 0; idx < INDEX_COUNT; idx = idx + 1) begin
            index_flat[idx*INDEX_W +: INDEX_W] = index_mem[idx];
            weight_flat[idx*WEIGHT_W +: WEIGHT_W] = weight_mem[idx];
        end

        for (idx = 0; idx < VEC_COUNT; idx = idx + 1) begin
            valid_vec[idx] = valid_mem[idx];
        end

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        cycles_waited = 0;
        while (!done && cycles_waited < 100) begin
            @(posedge clk);
            #1;
            cycles_waited = cycles_waited + 1;
        end

        if (!done) begin
            $display("ERROR: sparse did not assert done within timeout");
            mismatches = mismatches + 1;
        end

        if (output_act !== expected_mem[0]) begin
            $display("ERROR: output_act got=%02x expected=%02x", output_act, expected_mem[0]);
            mismatches = mismatches + 1;
        end

        if (output_acc !== $signed(expected_stats[0])) begin
            $display("ERROR: output_acc got=%0d expected=%0d", output_acc, $signed(expected_stats[0]));
            mismatches = mismatches + 1;
        end

        if (active_cycle_count !== expected_stats[1]) begin
            $display("ERROR: active_cycle_count got=%0d expected=%0d", active_cycle_count, expected_stats[1]);
            mismatches = mismatches + 1;
        end

        if (skipped_vector_count !== expected_stats[2]) begin
            $display("ERROR: skipped_vector_count got=%0d expected=%0d", skipped_vector_count, expected_stats[2]);
            mismatches = mismatches + 1;
        end

        if (cycle_count !== expected_stats[4]) begin
            $display("ERROR: cycle_count got=%0d expected=%0d", cycle_count, expected_stats[4]);
            mismatches = mismatches + 1;
        end

        if (expected_stats[4] !== expected_stats[1] + expected_stats[2]) begin
            $display("ERROR: sparse stats inconsistent total=%0d active+skipped=%0d",
                     expected_stats[4], expected_stats[1] + expected_stats[2]);
            mismatches = mismatches + 1;
        end

        if (active_cycle_count >= expected_stats[3]) begin
            $display("ERROR: active sparse cycles did not decrease: active=%0d dense=%0d", active_cycle_count, expected_stats[3]);
            mismatches = mismatches + 1;
        end

        if (cycle_count >= expected_stats[3]) begin
            $display("ERROR: total sparse cycles did not decrease: total=%0d dense=%0d", cycle_count, expected_stats[3]);
            mismatches = mismatches + 1;
        end

        if (mismatches == 0) begin
            $display("target=sparse mismatches=0 PASS active_cycles=%0d dense_cycles=%0d skipped_vectors=%0d",
                     active_cycle_count, expected_stats[3], skipped_vector_count);
            $finish;
        end else begin
            $display("target=sparse mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

endmodule

`default_nettype wire
