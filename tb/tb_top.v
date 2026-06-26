`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_top;

    localparam integer IN_H = 4;
    localparam integer IN_W = 4;
    localparam integer IN_C = 2;
    localparam integer CONV_OUT_C = 3;
    localparam integer POOL_OUT_H = 2;
    localparam integer POOL_OUT_W = 2;
    localparam integer INSTR_COUNT = 4;
    localparam integer CASE_COUNT = 5;
    localparam integer STATUS_COUNT = 10;
    localparam integer ADAPT_INTERVAL_COUNT = 8;
    localparam integer ADAPT_COUNTER_W = 16;
    localparam integer ADAPT_SCORE_MAX = 8;
    localparam integer DATA_W = `EG2C_DATA_W;
    localparam integer WEIGHT_W = `EG2C_WEIGHT_W;
    localparam integer INSTR_W = `EG2C_INSTR_W;

    localparam integer INPUT_COUNT = IN_H * IN_W * IN_C;
    localparam integer WEIGHT_COUNT = 3 * 3 * IN_C * CONV_OUT_C;
    localparam integer OUTPUT_COUNT = POOL_OUT_H * POOL_OUT_W * CONV_OUT_C;

    reg clk;
    reg rst_n;
    reg start;
    reg signed [DATA_W-1:0] score;
    reg signed [DATA_W-1:0] threshold;
    reg adapt_enable;
    reg [31:0] adapt_score_count;
    reg signed [DATA_W-1:0] adapt_initial_threshold;
    reg [INSTR_COUNT*INSTR_W-1:0] coarse_instr_flat;
    reg [INSTR_COUNT*INSTR_W-1:0] precise_instr_flat;
    reg [INPUT_COUNT*DATA_W-1:0] input_flat;
    reg [WEIGHT_COUNT*WEIGHT_W-1:0] coarse_weight_flat;
    reg [WEIGHT_COUNT*WEIGHT_W-1:0] precise_weight_flat;
    reg [(ADAPT_INTERVAL_COUNT+1)*DATA_W-1:0] adapt_bounds_flat;
    reg [ADAPT_SCORE_MAX*DATA_W-1:0] adapt_scores_flat;

    wire [OUTPUT_COUNT*DATA_W-1:0] selected_flat;
    wire precise_en;
    wire busy;
    wire done;
    wire error;
    wire [31:0] cycle_count;
    wire [31:0] converter_cycle_count;
    wire [7:0] converter_op_count;
    wire [31:0] sparse_skipped_count;
    wire adapt_done;
    wire signed [DATA_W-1:0] threshold_out;
    wire [31:0] adapt_sample_count;
    wire [31:0] adapt_ignored_sample_count;
    wire [7:0] adapt_selected_interval;
    wire [ADAPT_INTERVAL_COUNT*ADAPT_COUNTER_W-1:0] adapt_histogram_snapshot;

    reg [DATA_W-1:0] input_mem [0:INPUT_COUNT-1];
    reg [WEIGHT_W-1:0] coarse_weight_mem [0:WEIGHT_COUNT-1];
    reg [WEIGHT_W-1:0] precise_weight_mem [0:WEIGHT_COUNT-1];
    reg [INSTR_W-1:0] coarse_instr_mem [0:CASE_COUNT*INSTR_COUNT-1];
    reg [INSTR_W-1:0] precise_instr_mem [0:CASE_COUNT*INSTR_COUNT-1];
    reg [DATA_W-1:0] score_mem [0:CASE_COUNT-1];
    reg [DATA_W-1:0] threshold_mem [0:CASE_COUNT-1];
    reg [DATA_W-1:0] adapt_initial_threshold_mem [0:CASE_COUNT-1];
    reg adapt_enable_mem [0:CASE_COUNT-1];
    reg [31:0] adapt_length_mem [0:CASE_COUNT-1];
    reg [DATA_W-1:0] adapt_score_mem [0:CASE_COUNT*ADAPT_SCORE_MAX-1];
    reg [DATA_W-1:0] adapt_bound_mem [0:ADAPT_INTERVAL_COUNT];
    reg [DATA_W-1:0] expected_mem [0:CASE_COUNT*OUTPUT_COUNT-1];
    reg [31:0] expected_status [0:CASE_COUNT*STATUS_COUNT-1];
    reg [31:0] expected_histogram [0:CASE_COUNT*ADAPT_INTERVAL_COUNT-1];

    integer idx;
    integer case_idx;
    integer status_idx;
    integer interval_idx;
    integer mismatches;
    integer cycles_waited;
    reg [DATA_W-1:0] got;
    reg [DATA_W-1:0] expected;
    reg [ADAPT_COUNTER_W-1:0] got_hist;
    reg [ADAPT_COUNTER_W-1:0] expected_hist;

    eg2c_integrated_top #(
        .INSTR_COUNT(INSTR_COUNT),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .IN_C(IN_C),
        .CONV_OUT_C(CONV_OUT_C),
        .POOL_OUT_H(POOL_OUT_H),
        .POOL_OUT_W(POOL_OUT_W),
        .ADAPT_INTERVAL_COUNT(ADAPT_INTERVAL_COUNT),
        .ADAPT_COUNTER_W(ADAPT_COUNTER_W),
        .ADAPT_SCORE_COUNT(ADAPT_SCORE_MAX)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .score_i(score),
        .threshold_i(threshold),
        .adapt_enable_i(adapt_enable),
        .adapt_score_count_i(adapt_score_count),
        .adapt_initial_threshold_i(adapt_initial_threshold),
        .adapt_interval_bounds_i(adapt_bounds_flat),
        .adapt_scores_i(adapt_scores_flat),
        .coarse_instr_mem_i(coarse_instr_flat),
        .precise_instr_mem_i(precise_instr_flat),
        .input_act_i(input_flat),
        .coarse_weight_i(coarse_weight_flat),
        .precise_weight_i(precise_weight_flat),
        .selected_act_o(selected_flat),
        .precise_en_o(precise_en),
        .busy_o(busy),
        .done_o(done),
        .error_o(error),
        .cycle_count_o(cycle_count),
        .converter_cycle_count_o(converter_cycle_count),
        .converter_op_count_o(converter_op_count),
        .sparse_skipped_count_o(sparse_skipped_count),
        .adapt_done_o(adapt_done),
        .threshold_o(threshold_out),
        .adapt_sample_count_o(adapt_sample_count),
        .adapt_ignored_sample_count_o(adapt_ignored_sample_count),
        .adapt_selected_interval_o(adapt_selected_interval),
        .adapt_histogram_snapshot_o(adapt_histogram_snapshot)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/top/wave.vcd");
            $dumpvars(0, tb_top);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        score = '0;
        threshold = '0;
        adapt_enable = 1'b0;
        adapt_score_count = 32'd0;
        adapt_initial_threshold = '0;
        coarse_instr_flat = '0;
        precise_instr_flat = '0;
        input_flat = '0;
        coarse_weight_flat = '0;
        precise_weight_flat = '0;
        adapt_bounds_flat = '0;
        adapt_scores_flat = '0;

        $readmemh("sim/build/top/input_act.hex", input_mem);
        $readmemh("sim/build/top/coarse_weights.hex", coarse_weight_mem);
        $readmemh("sim/build/top/precise_weights.hex", precise_weight_mem);
        $readmemh("sim/build/top/coarse_instr.hex", coarse_instr_mem);
        $readmemh("sim/build/top/precise_instr.hex", precise_instr_mem);
        $readmemh("sim/build/top/scores.hex", score_mem);
        $readmemh("sim/build/top/thresholds.hex", threshold_mem);
        $readmemh("sim/build/top/adapt_initial_thresholds.hex", adapt_initial_threshold_mem);
        $readmemb("sim/build/top/adapt_enable.bin", adapt_enable_mem);
        $readmemh("sim/build/top/adapt_lengths.hex", adapt_length_mem);
        $readmemh("sim/build/top/adapt_scores.hex", adapt_score_mem);
        $readmemh("sim/build/top/boundaries.hex", adapt_bound_mem);
        $readmemh("sim/build/top/expected.hex", expected_mem);
        $readmemh("sim/build/top/expected_status.hex", expected_status);
        $readmemh("sim/build/top/expected_histogram.hex", expected_histogram);

        check_loaded_data();

        for (idx = 0; idx < INPUT_COUNT; idx = idx + 1) begin
            input_flat[idx*DATA_W +: DATA_W] = input_mem[idx];
        end
        for (idx = 0; idx < WEIGHT_COUNT; idx = idx + 1) begin
            coarse_weight_flat[idx*WEIGHT_W +: WEIGHT_W] = coarse_weight_mem[idx];
            precise_weight_flat[idx*WEIGHT_W +: WEIGHT_W] = precise_weight_mem[idx];
        end
        for (idx = 0; idx < ADAPT_INTERVAL_COUNT + 1; idx = idx + 1) begin
            adapt_bounds_flat[idx*DATA_W +: DATA_W] = adapt_bound_mem[idx];
        end

        for (case_idx = 0; case_idx < CASE_COUNT; case_idx = case_idx + 1) begin
            if (case_idx == 0) begin
                run_case(case_idx, 1'b1, 1'b1);
            end else if (case_idx == 2) begin
                run_case(case_idx, 1'b0, 1'b0);
            end else begin
                run_case(case_idx, 1'b1, 1'b0);
            end
        end

        if (mismatches == 0) begin
            $display("target=top mismatches=0 PASS cases=%0d", CASE_COUNT);
            $finish;
        end else begin
            $display("target=top mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

    task check_loaded_data;
        begin
            for (idx = 0; idx < INPUT_COUNT; idx = idx + 1) begin
                if (^input_mem[idx] === 1'bx) begin
                    $display("ERROR: top input_act[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < WEIGHT_COUNT; idx = idx + 1) begin
                if (^coarse_weight_mem[idx] === 1'bx || ^precise_weight_mem[idx] === 1'bx) begin
                    $display("ERROR: top weight[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < CASE_COUNT*INSTR_COUNT; idx = idx + 1) begin
                if (^coarse_instr_mem[idx] === 1'bx || ^precise_instr_mem[idx] === 1'bx) begin
                    $display("ERROR: top instr[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < CASE_COUNT; idx = idx + 1) begin
                if (^score_mem[idx] === 1'bx || ^threshold_mem[idx] === 1'bx ||
                    ^adapt_initial_threshold_mem[idx] === 1'bx ||
                    (adapt_enable_mem[idx] !== 1'b0 && adapt_enable_mem[idx] !== 1'b1) ||
                    ^adapt_length_mem[idx] === 1'bx) begin
                    $display("ERROR: top case control[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < CASE_COUNT*ADAPT_SCORE_MAX; idx = idx + 1) begin
                if (^adapt_score_mem[idx] === 1'bx) begin
                    $display("ERROR: top adapt_score[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < ADAPT_INTERVAL_COUNT + 1; idx = idx + 1) begin
                if (^adapt_bound_mem[idx] === 1'bx) begin
                    $display("ERROR: top boundary[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < CASE_COUNT*OUTPUT_COUNT; idx = idx + 1) begin
                if (^expected_mem[idx] === 1'bx) begin
                    $display("ERROR: top expected[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < CASE_COUNT*STATUS_COUNT; idx = idx + 1) begin
                if (^expected_status[idx] === 1'bx) begin
                    $display("ERROR: top expected_status[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
            for (idx = 0; idx < CASE_COUNT*ADAPT_INTERVAL_COUNT; idx = idx + 1) begin
                if (^expected_histogram[idx] === 1'bx) begin
                    $display("ERROR: top expected_histogram[%0d] has X/Z after load", idx);
                    mismatches = mismatches + 1;
                end
            end
        end
    endtask

    task run_case;
        input integer case_id;
        input do_reset;
        input hold_start;
        begin
            for (idx = 0; idx < INSTR_COUNT; idx = idx + 1) begin
                coarse_instr_flat[idx*INSTR_W +: INSTR_W] = coarse_instr_mem[case_id*INSTR_COUNT + idx];
                precise_instr_flat[idx*INSTR_W +: INSTR_W] = precise_instr_mem[case_id*INSTR_COUNT + idx];
            end
            for (idx = 0; idx < ADAPT_SCORE_MAX; idx = idx + 1) begin
                adapt_scores_flat[idx*DATA_W +: DATA_W] = adapt_score_mem[case_id*ADAPT_SCORE_MAX + idx];
            end
            for (idx = 0; idx < ADAPT_INTERVAL_COUNT + 1; idx = idx + 1) begin
                adapt_bounds_flat[idx*DATA_W +: DATA_W] = adapt_bound_mem[idx];
            end

            score = score_mem[case_id];
            threshold = threshold_mem[case_id];
            adapt_enable = adapt_enable_mem[case_id];
            adapt_score_count = adapt_length_mem[case_id];
            adapt_initial_threshold = adapt_initial_threshold_mem[case_id];

            if (do_reset) begin
                rst_n = 1'b0;
                start = 1'b0;
                repeat (3) @(negedge clk);
                rst_n = 1'b1;
            end else begin
                rst_n = 1'b1;
                start = 1'b0;
                @(negedge clk);
            end

            #1;
            if (busy !== 1'b0) begin
                $display("ERROR: case %0d busy before start got=%0b expected=0", case_id, busy);
                mismatches = mismatches + 1;
            end
            if (done !== 1'b0) begin
                $display("ERROR: case %0d done before start got=%0b expected=0", case_id, done);
                mismatches = mismatches + 1;
            end

            @(negedge clk);
            start = 1'b1;
            @(posedge clk);
            #1;
            if (busy !== 1'b1) begin
                $display("ERROR: case %0d busy after accepted start got=%0b expected=1", case_id, busy);
                mismatches = mismatches + 1;
            end

            if (case_id == 1) begin
                adapt_enable = 1'b0;
                adapt_score_count = 32'd0;
                adapt_initial_threshold = 8'h55;
                adapt_bounds_flat = '0;
                adapt_scores_flat = '0;
            end

            if (!hold_start) begin
                @(negedge clk);
                start = 1'b0;
            end

            cycles_waited = 0;
            while (done !== 1'b1 && cycles_waited < 2500) begin
                @(posedge clk);
                #1;
                cycles_waited = cycles_waited + 1;
            end

            if (done !== 1'b1) begin
                $display("ERROR: case %0d top did not assert done within timeout", case_id);
                mismatches = mismatches + 1;
            end

            status_idx = case_id * STATUS_COUNT;
            if (precise_en) begin
                $display("top case=%0d path=precise cycles=%0d converter_cycles=%0d sparse_skipped=%0d error=%0b",
                         case_id, cycle_count, converter_cycle_count, sparse_skipped_count, error);
            end else begin
                $display("top case=%0d path=coarse cycles=%0d converter_cycles=%0d sparse_skipped=%0d error=%0b",
                         case_id, cycle_count, converter_cycle_count, sparse_skipped_count, error);
            end

            if (error !== expected_status[status_idx][0]) begin
                $display("ERROR: case %0d error got=%0b expected=%0b",
                         case_id, error, expected_status[status_idx][0]);
                mismatches = mismatches + 1;
            end
            if (precise_en !== expected_status[status_idx + 1][0]) begin
                $display("ERROR: case %0d path got=%0b expected=%0b",
                         case_id, precise_en, expected_status[status_idx + 1][0]);
                mismatches = mismatches + 1;
            end
            if (converter_op_count !== expected_status[status_idx + 2][7:0]) begin
                $display("ERROR: case %0d op_count got=%0d expected=%0d",
                         case_id, converter_op_count, expected_status[status_idx + 2][7:0]);
                mismatches = mismatches + 1;
            end
            if (converter_cycle_count !== expected_status[status_idx + 3]) begin
                $display("ERROR: case %0d converter_cycle_count got=%0d expected=%0d",
                         case_id, converter_cycle_count, expected_status[status_idx + 3]);
                mismatches = mismatches + 1;
            end
            if (sparse_skipped_count !== expected_status[status_idx + 4]) begin
                $display("ERROR: case %0d sparse_skipped_count got=%0d expected=%0d",
                         case_id, sparse_skipped_count, expected_status[status_idx + 4]);
                mismatches = mismatches + 1;
            end
            if (adapt_done !== expected_status[status_idx + 5][0]) begin
                $display("ERROR: case %0d adapt_done got=%0b expected=%0b",
                         case_id, adapt_done, expected_status[status_idx + 5][0]);
                mismatches = mismatches + 1;
            end
            if (threshold_out !== expected_status[status_idx + 6][DATA_W-1:0]) begin
                $display("ERROR: case %0d threshold_out got=%02x expected=%02x",
                         case_id, threshold_out, expected_status[status_idx + 6][DATA_W-1:0]);
                mismatches = mismatches + 1;
            end
            if (adapt_sample_count !== expected_status[status_idx + 7]) begin
                $display("ERROR: case %0d adapt_sample_count got=%0d expected=%0d",
                         case_id, adapt_sample_count, expected_status[status_idx + 7]);
                mismatches = mismatches + 1;
            end
            if (adapt_ignored_sample_count !== expected_status[status_idx + 8]) begin
                $display("ERROR: case %0d adapt_ignored_sample_count got=%0d expected=%0d",
                         case_id, adapt_ignored_sample_count, expected_status[status_idx + 8]);
                mismatches = mismatches + 1;
            end
            if (adapt_selected_interval !== expected_status[status_idx + 9][7:0]) begin
                $display("ERROR: case %0d adapt_selected_interval got=%0d expected=%0d",
                         case_id, adapt_selected_interval, expected_status[status_idx + 9][7:0]);
                mismatches = mismatches + 1;
            end

            for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                got = selected_flat[idx*DATA_W +: DATA_W];
                expected = expected_mem[case_id*OUTPUT_COUNT + idx];
                if (got !== expected) begin
                    $display("ERROR: case %0d output[%0d] got=%02x expected=%02x",
                             case_id, idx, got, expected);
                    mismatches = mismatches + 1;
                end
            end

            for (interval_idx = 0; interval_idx < ADAPT_INTERVAL_COUNT; interval_idx = interval_idx + 1) begin
                got_hist = adapt_histogram_snapshot[interval_idx*ADAPT_COUNTER_W +: ADAPT_COUNTER_W];
                expected_hist = expected_histogram[case_id*ADAPT_INTERVAL_COUNT + interval_idx][ADAPT_COUNTER_W-1:0];
                if (got_hist !== expected_hist) begin
                    $display("ERROR: case %0d histogram[%0d] got=%0d expected=%0d",
                             case_id, interval_idx, got_hist, expected_hist);
                    mismatches = mismatches + 1;
                end
            end

            @(posedge clk);
            #1;
            if (done !== 1'b0) begin
                $display("ERROR: case %0d done did not clear after one cycle", case_id);
                mismatches = mismatches + 1;
            end
            if (busy !== 1'b0) begin
                $display("ERROR: case %0d busy after done got=%0b expected=0", case_id, busy);
                mismatches = mismatches + 1;
            end
            if (hold_start) begin
                @(negedge clk);
                start = 1'b0;
            end
        end
    endtask

endmodule

`default_nettype wire
