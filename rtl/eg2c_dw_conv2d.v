`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_dw_conv2d #(
    parameter integer DATA_W   = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer ACC_W    = `EG2C_ACC_W,
    parameter integer IN_H     = 4,
    parameter integer IN_W     = 4,
    parameter integer CHANNELS = 4,
    parameter integer K_H      = 3,
    parameter integer K_W      = 3,
    parameter integer PAD_H    = 1,
    parameter integer PAD_W    = 1
) (
    input  wire                                     clk_i,
    input  wire                                     rst_ni,
    input  wire                                     start_i,
    input  wire [IN_H*IN_W*CHANNELS*DATA_W-1:0]    input_act_i,
    input  wire [K_H*K_W*CHANNELS*WEIGHT_W-1:0]    weight_i,
    output reg  [IN_H*IN_W*CHANNELS*DATA_W-1:0]    output_act_o,
    output reg                                      busy_o,
    output reg                                      done_o,
    output reg  [31:0]                              cycle_count_o
);

    localparam integer STATE_IDLE = 2'd0;
    localparam integer STATE_CALC = 2'd1;
    localparam integer STATE_DONE = 2'd2;

    reg [1:0] state_q;
    integer out_y_q;
    integer out_x_q;
    integer ch_q;
    integer ker_y_q;
    integer ker_x_q;
    reg signed [ACC_W-1:0] acc_q;

    integer in_y;
    integer in_x;
    integer out_index;
    reg signed [DATA_W-1:0] act_value;
    reg signed [WEIGHT_W-1:0] weight_value;
    reg signed [DATA_W+WEIGHT_W-1:0] product_value;
    reg signed [ACC_W-1:0] acc_next;
    reg kernel_last;

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

    function signed [WEIGHT_W-1:0] get_weight;
        input integer ky;
        input integer kx;
        input integer c;
        integer flat_index;
        begin
            flat_index = ((ky * K_W + kx) * CHANNELS + c) * WEIGHT_W;
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

    always @(out_y_q or out_x_q or ch_q or ker_y_q or ker_x_q or acc_q or input_act_i or weight_i) begin
        in_y = out_y_q + ker_y_q - PAD_H;
        in_x = out_x_q + ker_x_q - PAD_W;
        act_value = {DATA_W{1'b0}};
        weight_value = get_weight(ker_y_q, ker_x_q, ch_q);

        if (in_y >= 0 && in_y < IN_H && in_x >= 0 && in_x < IN_W) begin
            act_value = get_act(in_y, in_x, ch_q);
        end

        product_value = act_value * weight_value;
        acc_next = acc_q + {{(ACC_W-(DATA_W+WEIGHT_W)){product_value[DATA_W+WEIGHT_W-1]}}, product_value};
        kernel_last = (ker_y_q == K_H - 1) && (ker_x_q == K_W - 1);
        out_index = ((out_y_q * IN_W + out_x_q) * CHANNELS + ch_q) * DATA_W;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= STATE_IDLE;
            out_y_q       <= 0;
            out_x_q       <= 0;
            ch_q          <= 0;
            ker_y_q       <= 0;
            ker_x_q       <= 0;
            acc_q         <= {ACC_W{1'b0}};
            output_act_o  <= {(IN_H*IN_W*CHANNELS*DATA_W){1'b0}};
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
                        ker_y_q       <= 0;
                        ker_x_q       <= 0;
                        acc_q         <= {ACC_W{1'b0}};
                        output_act_o  <= {(IN_H*IN_W*CHANNELS*DATA_W){1'b0}};
                        cycle_count_o <= 32'd0;
                        busy_o        <= 1'b1;
                        state_q       <= STATE_CALC;
                    end
                end

                STATE_CALC: begin
                    cycle_count_o <= cycle_count_o + 32'd1;

                    if (kernel_last) begin
                        output_act_o[out_index +: DATA_W] <= saturate_int8(acc_next);
                        acc_q <= {ACC_W{1'b0}};
                        ker_y_q <= 0;
                        ker_x_q <= 0;

                        if (ch_q == CHANNELS - 1) begin
                            ch_q <= 0;
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
                            ch_q <= ch_q + 1;
                        end
                    end else begin
                        acc_q <= acc_next;
                        if (ker_x_q == K_W - 1) begin
                            ker_x_q <= 0;
                            ker_y_q <= ker_y_q + 1;
                        end else begin
                            ker_x_q <= ker_x_q + 1;
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
