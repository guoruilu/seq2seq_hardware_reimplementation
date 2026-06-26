`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_input_act_buffer #(
    parameter integer DATA_W = `EG2C_DATA_W
) (
    input  wire              valid_i,
    input  wire [DATA_W-1:0] data_i,
    output wire              valid_o,
    output wire [DATA_W-1:0] data_o
);

    assign valid_o = valid_i;
    assign data_o  = data_i;

endmodule

`default_nettype wire
