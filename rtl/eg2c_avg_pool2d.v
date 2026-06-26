`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_avg_pool2d #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer ACC_W  = `EG2C_ACC_W,
    parameter integer IN_H   = 4,
    parameter integer IN_W   = 4,
    parameter integer CHANNELS = 3,
    parameter integer POOL_H = 2,
    parameter integer POOL_W = 2,
    parameter integer STRIDE_H = 2,
    parameter integer STRIDE_W = 2,
    parameter integer OUT_H = 2,
    parameter integer OUT_W = 2
) (
    input  wire                                    clk_i,
    input  wire                                    rst_ni,
    input  wire                                    start_i,
    input  wire [IN_H*IN_W*CHANNELS*DATA_W-1:0]   input_act_i,
    output reg  [OUT_H*OUT_W*CHANNELS*DATA_W-1:0] output_act_o,
    output reg                                     busy_o,
    output reg                                     done_o,
    output reg  [31:0]                             cycle_count_o
);

    localparam integer STATE_IDLE = 2'd0;
    localparam integer STATE_CALC = 2'd1;
    localparam integer STATE_DONE = 2'd2;
    localparam integer POOL_ELEMS = POOL_H * POOL_W;

    reg [1:0] state_q;
    integer out_y_q;
    integer out_x_q;
    integer ch_q;
    integer pool_y_q;
    integer pool_x_q;
    reg signed [ACC_W-1:0] acc_q;

    integer in_y;
    integer in_x;
    integer out_index;
    reg signed [DATA_W-1:0] act_value;
    reg signed [ACC_W-1:0] acc_next;
    reg pool_last;

    function signed [DATA_W-1:0] get_act;
        input integer y;
        input integer x;
        input integer c;
        integer flat_index;
        begin
            flat_index = ((y * IN_W + x) * CHANNELS + c) * DATA_W;
            get_act = input_act_i[flat_index +: DATA_W];
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

    always @(out_y_q or out_x_q or ch_q or pool_y_q or pool_x_q or acc_q or input_act_i) begin
        in_y = out_y_q * STRIDE_H + pool_y_q;
        in_x = out_x_q * STRIDE_W + pool_x_q;
        act_value = get_act(in_y, in_x, ch_q);
        acc_next = acc_q + {{(ACC_W-DATA_W){act_value[DATA_W-1]}}, act_value};
        pool_last = (pool_y_q == POOL_H - 1) && (pool_x_q == POOL_W - 1);
        out_index = ((out_y_q * OUT_W + out_x_q) * CHANNELS + ch_q) * DATA_W;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= STATE_IDLE;
            out_y_q       <= 0;
            out_x_q       <= 0;
            ch_q          <= 0;
            pool_y_q      <= 0;
            pool_x_q      <= 0;
            acc_q         <= {ACC_W{1'b0}};
            output_act_o  <= {(OUT_H*OUT_W*CHANNELS*DATA_W){1'b0}};
            busy_o        <= 1'b0;
            done_o        <= 1'b0;
            cycle_count_o <= 32'd0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        out_y_q       <= 0;
                        out_x_q       <= 0;
                        ch_q          <= 0;
                        pool_y_q      <= 0;
                        pool_x_q      <= 0;
                        acc_q         <= {ACC_W{1'b0}};
                        output_act_o  <= {(OUT_H*OUT_W*CHANNELS*DATA_W){1'b0}};
                        cycle_count_o <= 32'd0;
                        busy_o        <= 1'b1;
                        state_q       <= STATE_CALC;
                    end
                end

                STATE_CALC: begin
                    cycle_count_o <= cycle_count_o + 32'd1;

                    if (pool_last) begin
                        output_act_o[out_index +: DATA_W] <= saturate_int8(acc_next / POOL_ELEMS);
                        acc_q <= {ACC_W{1'b0}};
                        pool_y_q <= 0;
                        pool_x_q <= 0;

                        if (ch_q == CHANNELS - 1) begin
                            ch_q <= 0;
                            if (out_x_q == OUT_W - 1) begin
                                out_x_q <= 0;
                                if (out_y_q == OUT_H - 1) begin
                                    out_y_q <= 0;
                                    state_q <= STATE_DONE;
                                end else begin
                                    out_y_q <= out_y_q + 1;
                                end
                            end else begin
                                out_x_q <= out_x_q + 1;
                            end
                        end else begin
                            ch_q <= ch_q + 1;
                        end
                    end else begin
                        acc_q <= acc_next;
                        if (pool_x_q == POOL_W - 1) begin
                            pool_x_q <= 0;
                            pool_y_q <= pool_y_q + 1;
                        end else begin
                            pool_x_q <= pool_x_q + 1;
                        end
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
