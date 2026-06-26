`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

// [IP] e-G2C integrated toy top -- paper Fig. 1, Fig. 2, and Fig. 6.
//   Behavioral implementation: YES.
//   Notes: Starts one selected dense converter path and optionally co-runs the
//   threshold adaptation engine for a future detector window.
module eg2c_integrated_top #(
    parameter integer DATA_W               = `EG2C_DATA_W,
    parameter integer WEIGHT_W             = `EG2C_WEIGHT_W,
    parameter integer INSTR_W              = `EG2C_INSTR_W,
    parameter integer INSTR_COUNT          = 4,
    parameter integer IN_H                 = 4,
    parameter integer IN_W                 = 4,
    parameter integer IN_C                 = 2,
    parameter integer CONV_OUT_C           = 3,
    parameter integer POOL_OUT_H           = 2,
    parameter integer POOL_OUT_W           = 2,
    parameter integer ADAPT_INTERVAL_COUNT = 8,
    parameter integer ADAPT_COUNTER_W      = 16,
    parameter integer ADAPT_SCORE_COUNT    = 8
) (
    input  wire                                                       clk_i,
    input  wire                                                       rst_ni,
    input  wire                                                       start_i,
    input  wire signed [DATA_W-1:0]                                   score_i,
    input  wire signed [DATA_W-1:0]                                   threshold_i,
    input  wire                                                       adapt_enable_i,
    input  wire [31:0]                                                adapt_score_count_i,
    input  wire signed [DATA_W-1:0]                                   adapt_initial_threshold_i,
    input  wire [(ADAPT_INTERVAL_COUNT+1)*DATA_W-1:0]                 adapt_interval_bounds_i,
    input  wire [ADAPT_SCORE_COUNT*DATA_W-1:0]                        adapt_scores_i,
    input  wire [INSTR_COUNT*INSTR_W-1:0]                             coarse_instr_mem_i,
    input  wire [INSTR_COUNT*INSTR_W-1:0]                             precise_instr_mem_i,
    input  wire [IN_H*IN_W*IN_C*DATA_W-1:0]                           input_act_i,
    input  wire [3*3*IN_C*CONV_OUT_C*WEIGHT_W-1:0]                    coarse_weight_i,
    input  wire [3*3*IN_C*CONV_OUT_C*WEIGHT_W-1:0]                    precise_weight_i,
    output reg  [POOL_OUT_H*POOL_OUT_W*CONV_OUT_C*DATA_W-1:0]         selected_act_o,
    output reg                                                        precise_en_o,
    output reg                                                        busy_o,
    output reg                                                        done_o,
    output reg                                                        error_o,
    output reg  [31:0]                                                cycle_count_o,
    output reg  [31:0]                                                converter_cycle_count_o,
    output reg  [7:0]                                                 converter_op_count_o,
    output reg  [31:0]                                                sparse_skipped_count_o,
    output reg                                                        adapt_done_o,
    output reg  signed [DATA_W-1:0]                                   threshold_o,
    output reg  [31:0]                                                adapt_sample_count_o,
    output reg  [31:0]                                                adapt_ignored_sample_count_o,
    output reg  [7:0]                                                 adapt_selected_interval_o,
    output reg  [ADAPT_INTERVAL_COUNT*ADAPT_COUNTER_W-1:0]            adapt_histogram_snapshot_o
);

    localparam integer OUT_WIDTH = POOL_OUT_H * POOL_OUT_W * CONV_OUT_C * DATA_W;

    localparam integer STATE_IDLE  = 2'd0;
    localparam integer STATE_START = 2'd1;
    localparam integer STATE_RUN   = 2'd2;
    localparam integer STATE_DONE  = 2'd3;

    reg [1:0] state_q;
    reg start_d_q;
    reg selected_precise_q;
    reg converter_done_q;
    reg adapt_enable_q;
    reg adapt_done_seen_q;
    reg adapt_update_sent_q;
    reg [31:0] adapt_score_idx_q;
    reg [31:0] adapt_score_count_q;
    reg signed [DATA_W-1:0] adapt_initial_threshold_q;
    reg [(ADAPT_INTERVAL_COUNT+1)*DATA_W-1:0] adapt_interval_bounds_q;
    reg [ADAPT_SCORE_COUNT*DATA_W-1:0] adapt_scores_q;

    reg coarse_start_q;
    reg precise_start_q;
    reg adapt_start_q;
    reg adapt_score_valid_q;
    reg adapt_update_q;
    reg signed [DATA_W-1:0] adapt_score_q;

    wire branch_precise_en;

    wire [OUT_WIDTH-1:0] coarse_output;
    wire coarse_done;
    wire coarse_error;
    wire [31:0] coarse_cycle_count;
    wire [7:0] coarse_op_count;

    wire [OUT_WIDTH-1:0] precise_output;
    wire precise_done;
    wire precise_error;
    wire [31:0] precise_cycle_count;
    wire [7:0] precise_op_count;

    wire adapt_done;
    wire signed [DATA_W-1:0] adapt_threshold;
    wire [31:0] adapt_sample_count_w;
    wire [31:0] adapt_ignored_sample_count_w;
    wire [7:0] adapt_selected_interval_w;
    wire [ADAPT_INTERVAL_COUNT*ADAPT_COUNTER_W-1:0] adapt_histogram_snapshot_w;
    wire selected_converter_done = selected_precise_q ? precise_done : coarse_done;
    wire selected_converter_error = selected_precise_q ? precise_error : coarse_error;
    wire [31:0] selected_converter_cycles = selected_precise_q ? precise_cycle_count : coarse_cycle_count;
    wire [7:0] selected_converter_ops = selected_precise_q ? precise_op_count : coarse_op_count;
    wire [OUT_WIDTH-1:0] selected_converter_output = selected_precise_q ? precise_output : coarse_output;
    wire start_pulse = start_i && !start_d_q;
    wire adapt_count_valid_i = !adapt_enable_i || (adapt_score_count_i <= ADAPT_SCORE_COUNT);
    wire all_work_done = (converter_done_q || selected_converter_done) &&
                         (!adapt_enable_q || adapt_done_seen_q || adapt_done);

    initial begin
        if (DATA_W != 8 || WEIGHT_W != 8) begin
            $fatal(1, "eg2c_integrated_top currently requires 8-bit activations and weights");
        end
        if (INSTR_W < 32) begin
            $fatal(1, "eg2c_integrated_top INSTR_W must be at least 32 for child opcode fields");
        end
        if (INSTR_COUNT <= 0) begin
            $fatal(1, "eg2c_integrated_top INSTR_COUNT must be positive");
        end
        if (ADAPT_SCORE_COUNT <= 0) begin
            $fatal(1, "eg2c_integrated_top ADAPT_SCORE_COUNT must be positive");
        end
    end

    function signed [DATA_W-1:0] get_adapt_score;
        input integer score_idx;
        integer flat_index;
        begin
            flat_index = score_idx * DATA_W;
            get_adapt_score = adapt_scores_q[flat_index +: DATA_W];
        end
    endfunction

    eg2c_detector_branch #(
        .DATA_W(DATA_W),
        .OUT_COUNT(POOL_OUT_H * POOL_OUT_W * CONV_OUT_C)
    ) u_branch (
        .score_i(score_i),
        .threshold_i(threshold_i),
        .coarse_act_i(coarse_output),
        .precise_act_i(precise_output),
        .precise_en_o(branch_precise_en),
        .selected_act_o()
    );

    eg2c_dense_pipeline #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .INSTR_W(INSTR_W),
        .INSTR_COUNT(INSTR_COUNT),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .IN_C(IN_C),
        .CONV_OUT_C(CONV_OUT_C),
        .POOL_OUT_H(POOL_OUT_H),
        .POOL_OUT_W(POOL_OUT_W)
    ) u_coarse_pipeline (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(coarse_start_q),
        .instr_mem_i(coarse_instr_mem_i),
        .input_act_i(input_act_i),
        .conv_weight_i(coarse_weight_i),
        .output_act_o(coarse_output),
        .busy_o(),
        .done_o(coarse_done),
        .error_o(coarse_error),
        .cycle_count_o(coarse_cycle_count),
        .op_count_o(coarse_op_count)
    );

    eg2c_dense_pipeline #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .INSTR_W(INSTR_W),
        .INSTR_COUNT(INSTR_COUNT),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .IN_C(IN_C),
        .CONV_OUT_C(CONV_OUT_C),
        .POOL_OUT_H(POOL_OUT_H),
        .POOL_OUT_W(POOL_OUT_W)
    ) u_precise_pipeline (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(precise_start_q),
        .instr_mem_i(precise_instr_mem_i),
        .input_act_i(input_act_i),
        .conv_weight_i(precise_weight_i),
        .output_act_o(precise_output),
        .busy_o(),
        .done_o(precise_done),
        .error_o(precise_error),
        .cycle_count_o(precise_cycle_count),
        .op_count_o(precise_op_count)
    );

    eg2c_adapt_engine #(
        .DATA_W(DATA_W),
        .COUNTER_W(ADAPT_COUNTER_W),
        .INTERVAL_COUNT(ADAPT_INTERVAL_COUNT)
    ) u_adapt (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(adapt_start_q),
        .score_valid_i(adapt_score_valid_q),
        .score_i(adapt_score_q),
        .update_i(adapt_update_q),
        .initial_threshold_i(adapt_initial_threshold_q),
        .interval_bounds_i(adapt_interval_bounds_q),
        .threshold_o(adapt_threshold),
        .busy_o(),
        .done_o(adapt_done),
        .sample_count_o(adapt_sample_count_w),
        .ignored_sample_count_o(adapt_ignored_sample_count_w),
        .selected_interval_o(adapt_selected_interval_w),
        .histogram_o(),
        .histogram_snapshot_o(adapt_histogram_snapshot_w)
    );

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q                 <= STATE_IDLE;
            start_d_q               <= 1'b0;
            selected_precise_q      <= 1'b0;
            converter_done_q        <= 1'b0;
            adapt_enable_q          <= 1'b0;
            adapt_done_seen_q       <= 1'b0;
            adapt_update_sent_q     <= 1'b0;
            adapt_score_idx_q       <= 32'd0;
            adapt_score_count_q     <= 32'd0;
            adapt_initial_threshold_q <= {DATA_W{1'b0}};
            adapt_interval_bounds_q <= {((ADAPT_INTERVAL_COUNT+1)*DATA_W){1'b0}};
            adapt_scores_q          <= {(ADAPT_SCORE_COUNT*DATA_W){1'b0}};
            coarse_start_q          <= 1'b0;
            precise_start_q         <= 1'b0;
            adapt_start_q           <= 1'b0;
            adapt_score_valid_q     <= 1'b0;
            adapt_update_q          <= 1'b0;
            adapt_score_q           <= {DATA_W{1'b0}};
            selected_act_o          <= {OUT_WIDTH{1'b0}};
            precise_en_o            <= 1'b0;
            busy_o                  <= 1'b0;
            done_o                  <= 1'b0;
            error_o                 <= 1'b0;
            cycle_count_o           <= 32'd0;
            converter_cycle_count_o <= 32'd0;
            converter_op_count_o    <= 8'd0;
            sparse_skipped_count_o  <= 32'd0;
            adapt_done_o            <= 1'b0;
            threshold_o             <= {DATA_W{1'b0}};
            adapt_sample_count_o    <= 32'd0;
            adapt_ignored_sample_count_o <= 32'd0;
            adapt_selected_interval_o <= 8'd0;
            adapt_histogram_snapshot_o <= {(ADAPT_INTERVAL_COUNT*ADAPT_COUNTER_W){1'b0}};
        end else begin
            start_d_q           <= start_i;
            done_o              <= 1'b0;
            coarse_start_q      <= 1'b0;
            precise_start_q     <= 1'b0;
            adapt_start_q       <= 1'b0;
            adapt_score_valid_q <= 1'b0;
            adapt_update_q      <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_pulse) begin
                        selected_precise_q      <= branch_precise_en;
                        precise_en_o            <= branch_precise_en;
                        converter_done_q        <= 1'b0;
                        adapt_enable_q          <= adapt_enable_i;
                        adapt_done_seen_q       <= !adapt_enable_i || !adapt_count_valid_i;
                        adapt_update_sent_q     <= 1'b0;
                        adapt_score_idx_q       <= 32'd0;
                        adapt_score_count_q     <= adapt_score_count_i;
                        adapt_initial_threshold_q <= adapt_initial_threshold_i;
                        adapt_interval_bounds_q <= adapt_interval_bounds_i;
                        adapt_scores_q          <= adapt_scores_i;
                        selected_act_o          <= {OUT_WIDTH{1'b0}};
                        error_o                 <= !adapt_count_valid_i;
                        cycle_count_o           <= 32'd0;
                        converter_cycle_count_o <= 32'd0;
                        converter_op_count_o    <= 8'd0;
                        sparse_skipped_count_o  <= 32'd0;
                        adapt_done_o            <= 1'b0;
                        threshold_o             <= threshold_i;
                        adapt_sample_count_o    <= 32'd0;
                        adapt_ignored_sample_count_o <= 32'd0;
                        adapt_selected_interval_o <= 8'd0;
                        adapt_histogram_snapshot_o <= {(ADAPT_INTERVAL_COUNT*ADAPT_COUNTER_W){1'b0}};
                        busy_o                  <= 1'b1;
                        state_q                 <= adapt_count_valid_i ? STATE_START : STATE_DONE;
                    end
                end

                STATE_START: begin
                    cycle_count_o <= cycle_count_o + 32'd1;
                    if (selected_precise_q) begin
                        precise_start_q <= 1'b1;
                    end else begin
                        coarse_start_q <= 1'b1;
                    end
                    if (adapt_enable_q) begin
                        adapt_start_q <= 1'b1;
                    end
                    state_q <= STATE_RUN;
                end

                STATE_RUN: begin
                    cycle_count_o <= cycle_count_o + 32'd1;

                    if (adapt_enable_q && !adapt_done_seen_q) begin
                        if (!adapt_update_sent_q) begin
                            if (adapt_score_count_q == 32'd0) begin
                                adapt_update_q      <= 1'b1;
                                adapt_update_sent_q <= 1'b1;
                            end else if (adapt_score_idx_q < adapt_score_count_q) begin
                                adapt_score_q       <= get_adapt_score(adapt_score_idx_q);
                                adapt_score_valid_q <= 1'b1;
                                adapt_score_idx_q   <= adapt_score_idx_q + 32'd1;
                                if (adapt_score_idx_q == adapt_score_count_q - 32'd1) begin
                                    adapt_update_q      <= 1'b1;
                                    adapt_update_sent_q <= 1'b1;
                                end
                            end
                        end

                        if (adapt_done) begin
                            adapt_done_seen_q <= 1'b1;
                            adapt_done_o      <= 1'b1;
                            threshold_o       <= adapt_threshold;
                            adapt_sample_count_o <= adapt_sample_count_w;
                            adapt_ignored_sample_count_o <= adapt_ignored_sample_count_w;
                            adapt_selected_interval_o <= adapt_selected_interval_w;
                            adapt_histogram_snapshot_o <= adapt_histogram_snapshot_w;
                        end
                    end

                    if (!converter_done_q && selected_converter_done) begin
                        converter_done_q        <= 1'b1;
                        converter_cycle_count_o <= selected_converter_cycles;
                        converter_op_count_o    <= selected_converter_ops;
                        if (selected_converter_error) begin
                            error_o <= 1'b1;
                            selected_act_o <= {OUT_WIDTH{1'b0}};
                        end else begin
                            selected_act_o <= selected_converter_output;
                        end
                    end

                    if (all_work_done) begin
                        state_q <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    state_q <= STATE_IDLE;
                end

                default: begin
                    busy_o  <= 1'b0;
                    error_o <= 1'b1;
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
