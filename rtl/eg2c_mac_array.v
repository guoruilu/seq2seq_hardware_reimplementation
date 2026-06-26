`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_mac_array #(
    parameter integer LANES    = `EG2C_LANE_COUNT,
    parameter integer DATA_W   = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer ACC_W    = `EG2C_ACC_W
) (
    input  wire                            clk_i,
    input  wire                            rst_ni,
    input  wire                            clear_i,
    input  wire                            valid_i,
    input  wire [LANES*DATA_W-1:0]         act_vec_i,
    input  wire [LANES*WEIGHT_W-1:0]       weight_vec_i,
    output wire [LANES*ACC_W-1:0]          acc_vec_o,
    output wire [LANES-1:0]                valid_vec_o
);

    genvar lane_idx;

    generate
        for (lane_idx = 0; lane_idx < LANES; lane_idx = lane_idx + 1) begin : g_lane
            eg2c_mac_lane #(
                .DATA_W(DATA_W),
                .WEIGHT_W(WEIGHT_W),
                .ACC_W(ACC_W)
            ) u_lane (
                .clk_i(clk_i),
                .rst_ni(rst_ni),
                .clear_i(clear_i),
                .valid_i(valid_i),
                .act_i(act_vec_i[lane_idx*DATA_W +: DATA_W]),
                .weight_i(weight_vec_i[lane_idx*WEIGHT_W +: WEIGHT_W]),
                .acc_o(acc_vec_o[lane_idx*ACC_W +: ACC_W]),
                .valid_o(valid_vec_o[lane_idx])
            );
        end
    endgenerate

endmodule

`default_nettype wire
