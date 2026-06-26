`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_dw_reuse_conv2d #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer IN_H = 4,
    parameter integer IN_W = 4,
    parameter integer CHANNELS = 4,
    parameter integer K_H = 3,
    parameter integer K_W = 3,
    parameter integer PAD_H = 1,
    parameter integer PAD_W = 1
) (
    input  wire                                  clk_i,
    input  wire                                  rst_ni,
    input  wire                                  start_i,
    input  wire [IN_H*IN_W*CHANNELS*DATA_W-1:0] input_act_i,
    input  wire [K_H*K_W*CHANNELS*WEIGHT_W-1:0] weight_i,
    output wire [IN_H*IN_W*CHANNELS*DATA_W-1:0] output_act_o,
    output wire                                  busy_o,
    output wire                                  done_o,
    output wire [31:0]                           simple_cycle_count_o,
    output wire [31:0]                           cir_cycle_count_o,
    output wire [31:0]                           drir_cycle_count_o
);

    localparam integer SIMPLE_CYCLES = IN_H * IN_W * CHANNELS * K_H * K_W;
    localparam integer CIR_CYCLES = (SIMPLE_CYCLES + 2) / 3;
    localparam integer DRIR_CYCLES = (SIMPLE_CYCLES + 1) / 2;

    wire [31:0] unused_dw_cycles;

    assign simple_cycle_count_o = SIMPLE_CYCLES[31:0];
    assign cir_cycle_count_o    = CIR_CYCLES[31:0];
    assign drir_cycle_count_o   = DRIR_CYCLES[31:0];

    eg2c_dw_conv2d #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .CHANNELS(CHANNELS),
        .K_H(K_H),
        .K_W(K_W),
        .PAD_H(PAD_H),
        .PAD_W(PAD_W)
    ) u_dw_reference (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(start_i),
        .input_act_i(input_act_i),
        .weight_i(weight_i),
        .output_act_o(output_act_o),
        .busy_o(busy_o),
        .done_o(done_o),
        .cycle_count_o(unused_dw_cycles)
    );

endmodule

`default_nettype wire
