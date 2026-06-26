`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_output_act_buffer #(
    parameter integer DATA_W = `EG2C_DATA_W
) (
    input  wire              clk_i,
    input  wire              rst_ni,
    input  wire              valid_i,
    input  wire [DATA_W-1:0] data_i,
    output reg               valid_o,
    output reg  [DATA_W-1:0] data_o
);

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_o <= 1'b0;
            data_o  <= {DATA_W{1'b0}};
        end else begin
            valid_o <= valid_i;
            data_o  <= data_i;
        end
    end

endmodule

`default_nettype wire
