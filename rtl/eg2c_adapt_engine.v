`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_adapt_engine #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer COUNTER_W = 16,
    parameter integer INTERVAL_COUNT = 8
) (
    input  wire                                           clk_i,
    input  wire                                           rst_ni,
    input  wire                                           start_i,
    input  wire                                           score_valid_i,
    input  wire signed [DATA_W-1:0]                       score_i,
    input  wire                                           update_i,
    input  wire signed [DATA_W-1:0]                       initial_threshold_i,
    input  wire [(INTERVAL_COUNT+1)*DATA_W-1:0]           interval_bounds_i,
    output reg  signed [DATA_W-1:0]                       threshold_o,
    output reg                                            busy_o,
    output reg                                            done_o,
    output reg  [31:0]                                    sample_count_o,
    output reg  [31:0]                                    ignored_sample_count_o,
    output reg  [7:0]                                     selected_interval_o,
    output reg  [INTERVAL_COUNT*COUNTER_W-1:0]            histogram_o,
    output reg  [INTERVAL_COUNT*COUNTER_W-1:0]            histogram_snapshot_o
);

    localparam integer STATE_IDLE = 2'd0;
    localparam integer STATE_RUN  = 2'd1;

    reg [1:0] state_q;

    integer classify_idx;
    integer argmin_idx;
    integer selected_idx;
    reg [COUNTER_W-1:0] selected_count;
    reg [COUNTER_W-1:0] score_interval_count;
    reg score_in_range;
    reg [7:0] score_interval;

    initial begin
        if (DATA_W != 8) begin
            $fatal(1, "eg2c_adapt_engine currently requires signed 8-bit scores and thresholds");
        end
        if (INTERVAL_COUNT <= 0) begin
            $fatal(1, "eg2c_adapt_engine INTERVAL_COUNT must be positive");
        end
        if (INTERVAL_COUNT > 255) begin
            $fatal(1, "eg2c_adapt_engine INTERVAL_COUNT must fit selected_interval_o");
        end
    end

    function signed [DATA_W-1:0] get_bound;
        input integer bound_idx;
        integer flat_index;
        begin
            flat_index = bound_idx * DATA_W;
            get_bound = interval_bounds_i[flat_index +: DATA_W];
        end
    endfunction

    function [COUNTER_W-1:0] get_hist;
        input [INTERVAL_COUNT*COUNTER_W-1:0] histogram_flat;
        input integer hist_idx;
        integer flat_index;
        begin
            flat_index = hist_idx * COUNTER_W;
            get_hist = histogram_flat[flat_index +: COUNTER_W];
        end
    endfunction

    function signed [DATA_W-1:0] interval_midpoint;
        input integer hist_idx;
        reg signed [DATA_W:0] lower_ext;
        reg signed [DATA_W:0] upper_ext;
        reg signed [DATA_W:0] midpoint_ext;
        begin
            lower_ext = get_bound(hist_idx);
            upper_ext = get_bound(hist_idx + 1);
            midpoint_ext = (lower_ext + upper_ext) / 2;
            interval_midpoint = midpoint_ext[DATA_W-1:0];
        end
    endfunction

    always @(score_i or interval_bounds_i) begin
        score_interval = 8'd0;
        score_in_range = 1'b0;
        for (classify_idx = 0; classify_idx < INTERVAL_COUNT; classify_idx = classify_idx + 1) begin
            if (!score_in_range) begin
                if (classify_idx == INTERVAL_COUNT - 1) begin
                    if (score_i >= get_bound(classify_idx) && score_i <= get_bound(classify_idx + 1)) begin
                        score_interval = classify_idx[7:0];
                        score_in_range = 1'b1;
                    end
                end else if (score_i >= get_bound(classify_idx) && score_i < get_bound(classify_idx + 1)) begin
                    score_interval = classify_idx[7:0];
                    score_in_range = 1'b1;
                end
            end
        end
    end

    always @(histogram_o) begin
        selected_idx = 0;
        selected_count = get_hist(histogram_o, 0);
        for (argmin_idx = 1; argmin_idx < INTERVAL_COUNT; argmin_idx = argmin_idx + 1) begin
            if (get_hist(histogram_o, argmin_idx) < selected_count) begin
                selected_idx = argmin_idx;
                selected_count = get_hist(histogram_o, argmin_idx);
            end
        end
    end

    always @(score_interval or histogram_o) begin
        score_interval_count = get_hist(histogram_o, score_interval);
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q                <= STATE_IDLE;
            threshold_o            <= {DATA_W{1'b0}};
            busy_o                 <= 1'b0;
            done_o                 <= 1'b0;
            sample_count_o         <= 32'd0;
            ignored_sample_count_o <= 32'd0;
            selected_interval_o    <= 8'd0;
            histogram_o            <= {INTERVAL_COUNT*COUNTER_W{1'b0}};
            histogram_snapshot_o   <= {INTERVAL_COUNT*COUNTER_W{1'b0}};
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        threshold_o            <= initial_threshold_i;
                        sample_count_o         <= 32'd0;
                        ignored_sample_count_o <= 32'd0;
                        selected_interval_o    <= 8'd0;
                        histogram_o            <= {INTERVAL_COUNT*COUNTER_W{1'b0}};
                        histogram_snapshot_o   <= {INTERVAL_COUNT*COUNTER_W{1'b0}};
                        busy_o  <= 1'b1;
                        state_q <= STATE_RUN;
                    end
                end

                STATE_RUN: begin
                    if (update_i) begin
                        selected_interval_o <= selected_idx[7:0];
                        threshold_o         <= interval_midpoint(selected_idx);
                        histogram_snapshot_o <= histogram_o;
                        histogram_o          <= {INTERVAL_COUNT*COUNTER_W{1'b0}};
                        busy_o  <= 1'b0;
                        done_o  <= 1'b1;
                        state_q <= STATE_IDLE;
                    end else if (score_valid_i) begin
                        sample_count_o <= sample_count_o + 32'd1;
                        if (score_in_range) begin
                            histogram_o[score_interval*COUNTER_W +: COUNTER_W] <=
                                score_interval_count + {{(COUNTER_W-1){1'b0}}, 1'b1};
                        end else begin
                            ignored_sample_count_o <= ignored_sample_count_o + 32'd1;
                        end
                    end
                end

                default: begin
                    busy_o  <= 1'b0;
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
