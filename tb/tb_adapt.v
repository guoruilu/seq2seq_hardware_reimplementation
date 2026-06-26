`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_adapt;

    localparam integer DATA_W = `EG2C_DATA_W;
    localparam integer COUNTER_W = 16;
    localparam integer INTERVAL_COUNT = 8;
    localparam integer BOUNDARY_COUNT = INTERVAL_COUNT + 1;
    localparam integer CASE_COUNT = 2;
    localparam integer TOTAL_SCORE_COUNT = 32;
    localparam integer STATS_PER_CASE = 5;

    reg clk;
    reg rst_n;
    reg start;
    reg score_valid;
    reg update;
    reg signed [DATA_W-1:0] score;
    reg signed [DATA_W-1:0] initial_threshold;
    reg [BOUNDARY_COUNT*DATA_W-1:0] boundaries_flat;
    wire signed [DATA_W-1:0] threshold;
    wire busy;
    wire done;
    wire [31:0] sample_count;
    wire [31:0] ignored_sample_count;
    wire [7:0] selected_interval;
    wire [INTERVAL_COUNT*COUNTER_W-1:0] histogram;
    wire [INTERVAL_COUNT*COUNTER_W-1:0] histogram_snapshot;

    reg [DATA_W-1:0] score_mem [0:TOTAL_SCORE_COUNT-1];
    reg [DATA_W-1:0] boundaries_mem [0:BOUNDARY_COUNT-1];
    reg [DATA_W-1:0] initial_threshold_mem [0:CASE_COUNT-1];
    reg [31:0] case_lengths [0:CASE_COUNT-1];
    reg [31:0] expected_histogram [0:CASE_COUNT*INTERVAL_COUNT-1];
    reg [31:0] expected_stats [0:CASE_COUNT*STATS_PER_CASE-1];

    integer idx;
    integer case_idx;
    integer score_idx;
    integer hist_idx;
    integer score_offset;
    integer stats_base;
    integer hist_base;
    integer mismatches;
    reg signed [DATA_W-1:0] expected_threshold;

    eg2c_adapt_engine #(
        .DATA_W(DATA_W),
        .COUNTER_W(COUNTER_W),
        .INTERVAL_COUNT(INTERVAL_COUNT)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .score_valid_i(score_valid),
        .score_i(score),
        .update_i(update),
        .initial_threshold_i(initial_threshold),
        .interval_bounds_i(boundaries_flat),
        .threshold_o(threshold),
        .busy_o(busy),
        .done_o(done),
        .sample_count_o(sample_count),
        .ignored_sample_count_o(ignored_sample_count),
        .selected_interval_o(selected_interval),
        .histogram_o(histogram),
        .histogram_snapshot_o(histogram_snapshot)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/adapt/wave.vcd");
            $dumpvars(0, tb_adapt);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        score_valid = 1'b0;
        update = 1'b0;
        score = '0;
        initial_threshold = '0;
        boundaries_flat = '0;

        $readmemh("sim/build/adapt/scores.hex", score_mem);
        $readmemh("sim/build/adapt/boundaries.hex", boundaries_mem);
        $readmemh("sim/build/adapt/initial_thresholds.hex", initial_threshold_mem);
        $readmemh("sim/build/adapt/case_lengths.hex", case_lengths);
        $readmemh("sim/build/adapt/expected_histogram.hex", expected_histogram);
        $readmemh("sim/build/adapt/expected_stats.hex", expected_stats);

        for (idx = 0; idx < TOTAL_SCORE_COUNT; idx = idx + 1) begin
            if (^score_mem[idx] === 1'bx) begin
                $display("ERROR: adapt score[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < BOUNDARY_COUNT; idx = idx + 1) begin
            if (^boundaries_mem[idx] === 1'bx) begin
                $display("ERROR: adapt boundary[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
            boundaries_flat[idx*DATA_W +: DATA_W] = boundaries_mem[idx];
        end

        for (idx = 0; idx < CASE_COUNT; idx = idx + 1) begin
            if (^initial_threshold_mem[idx] === 1'bx || ^case_lengths[idx] === 1'bx) begin
                $display("ERROR: adapt case metadata[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < CASE_COUNT*INTERVAL_COUNT; idx = idx + 1) begin
            if (^expected_histogram[idx] === 1'bx) begin
                $display("ERROR: adapt expected_histogram[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        for (idx = 0; idx < CASE_COUNT*STATS_PER_CASE; idx = idx + 1) begin
            if (^expected_stats[idx] === 1'bx) begin
                $display("ERROR: adapt expected_stats[%0d] has X/Z after load", idx);
                mismatches = mismatches + 1;
            end
        end

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        score_offset = 0;
        for (case_idx = 0; case_idx < CASE_COUNT; case_idx = case_idx + 1) begin
            stats_base = case_idx * STATS_PER_CASE;
            hist_base = case_idx * INTERVAL_COUNT;
            initial_threshold = initial_threshold_mem[case_idx];

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            #1;

            if (!busy) begin
                $display("ERROR: adapt case %0d did not assert busy after start", case_idx);
                mismatches = mismatches + 1;
            end

            if (threshold !== initial_threshold_mem[case_idx]) begin
                $display("ERROR: adapt case %0d initial threshold got=%0d expected=%0d",
                         case_idx, threshold, $signed(initial_threshold_mem[case_idx]));
                mismatches = mismatches + 1;
            end

            for (score_idx = 0; score_idx < case_lengths[case_idx]; score_idx = score_idx + 1) begin
                @(negedge clk);
                score = score_mem[score_offset + score_idx];
                score_valid = 1'b1;
                @(posedge clk);
                #1;
                if (!busy) begin
                    $display("ERROR: adapt case %0d busy dropped during score window", case_idx);
                    mismatches = mismatches + 1;
                end
            end
            @(negedge clk);
            score_valid = 1'b0;

            if (sample_count !== expected_stats[stats_base + 4]) begin
                $display("ERROR: adapt case %0d sample_count got=%0d expected=%0d",
                         case_idx, sample_count, expected_stats[stats_base + 4]);
                mismatches = mismatches + 1;
            end

            if (ignored_sample_count !== expected_stats[stats_base + 3]) begin
                $display("ERROR: adapt case %0d ignored_count got=%0d expected=%0d",
                         case_idx, ignored_sample_count, expected_stats[stats_base + 3]);
                mismatches = mismatches + 1;
            end

            for (hist_idx = 0; hist_idx < INTERVAL_COUNT; hist_idx = hist_idx + 1) begin
                if (histogram[hist_idx*COUNTER_W +: COUNTER_W] !==
                    expected_histogram[hist_base + hist_idx][COUNTER_W-1:0]) begin
                    $display("ERROR: adapt case %0d histogram[%0d] got=%0d expected=%0d",
                             case_idx, hist_idx,
                             histogram[hist_idx*COUNTER_W +: COUNTER_W],
                             expected_histogram[hist_base + hist_idx]);
                    mismatches = mismatches + 1;
                end
            end

            @(negedge clk);
            update = 1'b1;
            @(posedge clk);
            #1;
            update = 1'b0;

            if (!done) begin
                $display("ERROR: adapt case %0d did not assert done on update", case_idx);
                mismatches = mismatches + 1;
            end

            if (busy) begin
                $display("ERROR: adapt case %0d kept busy asserted after update", case_idx);
                mismatches = mismatches + 1;
            end

            expected_threshold = expected_stats[stats_base][DATA_W-1:0];
            if (threshold !== expected_threshold) begin
                $display("ERROR: adapt case %0d threshold got=%0d expected=%0d",
                         case_idx, threshold, expected_threshold);
                mismatches = mismatches + 1;
            end

            if (selected_interval !== expected_stats[stats_base + 1][7:0]) begin
                $display("ERROR: adapt case %0d selected_interval got=%0d expected=%0d",
                         case_idx, selected_interval, expected_stats[stats_base + 1]);
                mismatches = mismatches + 1;
            end

            for (hist_idx = 0; hist_idx < INTERVAL_COUNT; hist_idx = hist_idx + 1) begin
                if (histogram_snapshot[hist_idx*COUNTER_W +: COUNTER_W] !==
                    expected_histogram[hist_base + hist_idx][COUNTER_W-1:0]) begin
                    $display("ERROR: adapt case %0d snapshot[%0d] got=%0d expected=%0d",
                             case_idx, hist_idx,
                             histogram_snapshot[hist_idx*COUNTER_W +: COUNTER_W],
                             expected_histogram[hist_base + hist_idx]);
                    mismatches = mismatches + 1;
                end
                if (histogram[hist_idx*COUNTER_W +: COUNTER_W] !== {COUNTER_W{1'b0}}) begin
                    $display("ERROR: adapt case %0d histogram[%0d] was not reset after update",
                             case_idx, hist_idx);
                    mismatches = mismatches + 1;
                end
            end

            if (expected_stats[stats_base + 2] + expected_stats[stats_base + 3] !==
                expected_stats[stats_base + 4]) begin
                $display("ERROR: adapt case %0d expected stats inconsistent", case_idx);
                mismatches = mismatches + 1;
            end

            score_offset = score_offset + case_lengths[case_idx];
        end

        if (score_offset !== TOTAL_SCORE_COUNT) begin
            $display("ERROR: adapt consumed %0d scores, expected %0d", score_offset, TOTAL_SCORE_COUNT);
            mismatches = mismatches + 1;
        end

        if (mismatches == 0) begin
            $display("target=adapt mismatches=0 PASS cases=%0d final_threshold=%0d selected_interval=%0d",
                     CASE_COUNT, threshold, selected_interval);
            $finish;
        end else begin
            $display("target=adapt mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

endmodule

`default_nettype wire
