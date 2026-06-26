`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_detector_branch #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer OUT_COUNT = 8
) (
    input  wire signed [DATA_W-1:0]               score_i,
    input  wire signed [DATA_W-1:0]               threshold_i,
    input  wire [OUT_COUNT*DATA_W-1:0]            coarse_act_i,
    input  wire [OUT_COUNT*DATA_W-1:0]            precise_act_i,
    output wire                                   precise_en_o,
    output wire [OUT_COUNT*DATA_W-1:0]            selected_act_o
);

    assign precise_en_o = (score_i >= threshold_i);
    assign selected_act_o = precise_en_o ? precise_act_i : coarse_act_i;

endmodule

`default_nettype wire
