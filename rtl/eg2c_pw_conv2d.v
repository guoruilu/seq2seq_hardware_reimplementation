`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_pw_conv2d #(
    parameter integer DATA_W   = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer ACC_W    = `EG2C_ACC_W,
    parameter integer IN_H     = 4,
    parameter integer IN_W     = 4,
    parameter integer IN_C     = 4,
    parameter integer OUT_C    = 5,
    parameter integer SPARSE_VEC_LEN = 3,
    parameter integer SPARSE_VEC_COUNT = (IN_C + ((SPARSE_VEC_LEN > 0) ? SPARSE_VEC_LEN : 1) - 1) /
                                         ((SPARSE_VEC_LEN > 0) ? SPARSE_VEC_LEN : 1)
) (
    input  wire                                    clk_i,
    input  wire                                    rst_ni,
    input  wire                                    start_i,
    input  wire                                    sparse_enable_i,
    input  wire [IN_H*IN_W*IN_C*DATA_W-1:0]       input_act_i,
    input  wire [IN_C*OUT_C*WEIGHT_W-1:0]         weight_i,
    input  wire [OUT_C*SPARSE_VEC_COUNT-1:0]        sparse_vector_valid_i,
    output reg  [IN_H*IN_W*OUT_C*DATA_W-1:0]      output_act_o,
    output reg                                     busy_o,
    output reg                                     done_o,
    output reg  [31:0]                             cycle_count_o,
    output reg  [31:0]                             active_cycle_count_o,
    output reg  [31:0]                             skipped_vector_count_o
);

    localparam integer STATE_IDLE = 2'd0;
    localparam integer STATE_CALC = 2'd1;
    localparam integer STATE_DONE = 2'd2;
    localparam integer ACC_TERMS = IN_C;
    localparam integer ACC_REQ_W = DATA_W + WEIGHT_W + ((ACC_TERMS > 1) ? $clog2(ACC_TERMS) : 0);
    localparam integer SPARSE_VEC_LEN_SAFE = (SPARSE_VEC_LEN > 0) ? SPARSE_VEC_LEN : 1;
    localparam integer SPARSE_VEC_COUNT_REQ = (IN_C + SPARSE_VEC_LEN_SAFE - 1) / SPARSE_VEC_LEN_SAFE;

    reg [1:0] state_q;
    integer out_y_q;
    integer out_x_q;
    integer out_c_q;
    integer in_c_q;
    reg signed [ACC_W-1:0] acc_q;

    integer out_index;
    integer sparse_vec_index;
    integer sparse_valid_index;
    integer next_skip_in_c;
    reg signed [DATA_W-1:0] act_value;
    reg signed [WEIGHT_W-1:0] weight_value;
    reg signed [DATA_W+WEIGHT_W-1:0] product_value;
    reg signed [ACC_W-1:0] acc_next;
    reg channel_last;
    reg vector_start;
    reg vector_skip;
    reg vector_last;

    function signed [DATA_W-1:0] get_act;
        input integer y;
        input integer x;
        input integer c;
        integer flat_index;
        begin
            flat_index = ((y * IN_W + x) * IN_C + c) * DATA_W;
            get_act = input_act_i[flat_index +: DATA_W];
        end
    endfunction

    function signed [WEIGHT_W-1:0] get_weight;
        input integer ic;
        input integer oc;
        integer flat_index;
        begin
            flat_index = (ic * OUT_C + oc) * WEIGHT_W;
            get_weight = weight_i[flat_index +: WEIGHT_W];
        end
    endfunction

    function [DATA_W-1:0] saturate_int8;
        input signed [ACC_W-1:0] value;
        begin
            if (value > 32'sd127) begin
                saturate_int8 = 8'h7f;
            end else if (value < -32'sd128) begin
                saturate_int8 = 8'h80;
            end else begin
                saturate_int8 = value[DATA_W-1:0];
            end
        end
    endfunction

    initial begin
        if (DATA_W != 8 || WEIGHT_W != 8) begin
            $fatal(1, "eg2c_pw_conv2d currently requires 8-bit activations and weights");
        end
        if (ACC_W < ACC_REQ_W) begin
            $fatal(1, "eg2c_pw_conv2d ACC_W is too small for the full channel accumulation");
        end
        if (SPARSE_VEC_LEN <= 0) begin
            $fatal(1, "eg2c_pw_conv2d SPARSE_VEC_LEN must be positive");
        end
        if (SPARSE_VEC_COUNT != SPARSE_VEC_COUNT_REQ) begin
            $fatal(1, "eg2c_pw_conv2d SPARSE_VEC_COUNT does not match SPARSE_VEC_LEN and input channels");
        end
    end

    always @(out_y_q or out_x_q or out_c_q or in_c_q or acc_q or input_act_i or weight_i or sparse_enable_i or sparse_vector_valid_i) begin
        act_value = get_act(out_y_q, out_x_q, in_c_q);
        weight_value = get_weight(in_c_q, out_c_q);
        sparse_vec_index = in_c_q / SPARSE_VEC_LEN_SAFE;
        sparse_valid_index = out_c_q * SPARSE_VEC_COUNT + sparse_vec_index;
        next_skip_in_c = in_c_q + SPARSE_VEC_LEN_SAFE;
        // vector_valid marks sparse weight vectors with at least one nonzero term.
        vector_start = ((in_c_q - (sparse_vec_index * SPARSE_VEC_LEN_SAFE)) == 0);
        vector_skip = sparse_enable_i && vector_start && !sparse_vector_valid_i[sparse_valid_index];
        vector_last = (sparse_vec_index == SPARSE_VEC_COUNT - 1);
        product_value = act_value * weight_value;
        acc_next = acc_q + {{(ACC_W-(DATA_W+WEIGHT_W)){product_value[DATA_W+WEIGHT_W-1]}}, product_value};
        channel_last = (in_c_q == IN_C - 1);
        out_index = ((out_y_q * IN_W + out_x_q) * OUT_C + out_c_q) * DATA_W;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= STATE_IDLE;
            out_y_q       <= 0;
            out_x_q       <= 0;
            out_c_q       <= 0;
            in_c_q        <= 0;
            acc_q         <= {ACC_W{1'b0}};
            output_act_o  <= {(IN_H*IN_W*OUT_C*DATA_W){1'b0}};
            busy_o        <= 1'b0;
            done_o        <= 1'b0;
            cycle_count_o <= 32'd0;
            active_cycle_count_o <= 32'd0;
            skipped_vector_count_o <= 32'd0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        out_y_q       <= 0;
                        out_x_q       <= 0;
                        out_c_q       <= 0;
                        in_c_q        <= 0;
                        acc_q         <= {ACC_W{1'b0}};
                        output_act_o  <= {(IN_H*IN_W*OUT_C*DATA_W){1'b0}};
                        cycle_count_o <= 32'd0;
                        active_cycle_count_o <= 32'd0;
                        skipped_vector_count_o <= 32'd0;
                        busy_o        <= 1'b1;
                        state_q       <= STATE_CALC;
                    end
                end

                STATE_CALC: begin
                    cycle_count_o <= cycle_count_o + 32'd1;

                    if (vector_skip) begin
                        skipped_vector_count_o <= skipped_vector_count_o + 32'd1;
                        if (vector_last) begin
                            output_act_o[out_index +: DATA_W] <= saturate_int8(acc_q);
                            acc_q  <= {ACC_W{1'b0}};
                            in_c_q <= 0;

                            if (out_c_q == OUT_C - 1) begin
                                out_c_q <= 0;
                                if (out_x_q == IN_W - 1) begin
                                    out_x_q <= 0;
                                    if (out_y_q == IN_H - 1) begin
                                        out_y_q <= 0;
                                        state_q <= STATE_DONE;
                                    end else begin
                                        out_y_q <= out_y_q + 1;
                                    end
                                end else begin
                                    out_x_q <= out_x_q + 1;
                                end
                            end else begin
                                out_c_q <= out_c_q + 1;
                            end
                        end else begin
                            in_c_q <= next_skip_in_c;
                        end
                    end else if (channel_last) begin
                        active_cycle_count_o <= active_cycle_count_o + 32'd1;
                        output_act_o[out_index +: DATA_W] <= saturate_int8(acc_next);
                        acc_q  <= {ACC_W{1'b0}};
                        in_c_q <= 0;

                        if (out_c_q == OUT_C - 1) begin
                            out_c_q <= 0;
                            if (out_x_q == IN_W - 1) begin
                                out_x_q <= 0;
                                if (out_y_q == IN_H - 1) begin
                                    out_y_q <= 0;
                                    state_q <= STATE_DONE;
                                end else begin
                                    out_y_q <= out_y_q + 1;
                                end
                            end else begin
                                out_x_q <= out_x_q + 1;
                            end
                        end else begin
                            out_c_q <= out_c_q + 1;
                        end
                    end else begin
                        active_cycle_count_o <= active_cycle_count_o + 32'd1;
                        acc_q  <= acc_next;
                        in_c_q <= in_c_q + 1;
                    end
                end

                STATE_DONE: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    state_q <= STATE_IDLE;
                end

                default: begin
                    state_q <= STATE_IDLE;
                    busy_o  <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
