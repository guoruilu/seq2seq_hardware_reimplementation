`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_mac_lane #(
    parameter integer DATA_W   = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer ACC_W    = `EG2C_ACC_W
) (
    input  wire                         clk_i,
    input  wire                         rst_ni,
    input  wire                         clear_i,
    input  wire                         valid_i,
    input  wire signed [DATA_W-1:0]     act_i,
    input  wire signed [WEIGHT_W-1:0]   weight_i,
    output reg  signed [ACC_W-1:0]      acc_o,
    output reg                          valid_o
);

    wire signed [DATA_W+WEIGHT_W-1:0] product;

    assign product = act_i * weight_i;

    initial begin
        if (ACC_W < DATA_W + WEIGHT_W) begin
            $fatal(1, "eg2c_mac_lane requires ACC_W >= DATA_W + WEIGHT_W");
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            acc_o   <= {ACC_W{1'b0}};
            valid_o <= 1'b0;
        end else if (clear_i) begin
            acc_o   <= {ACC_W{1'b0}};
            valid_o <= 1'b0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) begin
                acc_o <= acc_o + {{(ACC_W-(DATA_W+WEIGHT_W)){product[DATA_W+WEIGHT_W-1]}}, product};
            end
        end
    end

endmodule

`default_nettype wire
