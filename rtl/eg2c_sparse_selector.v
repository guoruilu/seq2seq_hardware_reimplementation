`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_sparse_selector #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer INDEX_W = `EG2C_INDEX_W,
    parameter integer ACT_COUNT = 16
) (
    input  wire [ACT_COUNT*DATA_W-1:0] act_vec_i,
    input  wire [INDEX_W-1:0]          index_i,
    output reg  [DATA_W-1:0]           act_o
);

    integer idx;

    initial begin
        if ((2 ** INDEX_W) < ACT_COUNT) begin
            $fatal(1, "eg2c_sparse_selector INDEX_W cannot address every activation");
        end
    end

    always @(act_vec_i or index_i) begin
        act_o = {DATA_W{1'b0}};
        for (idx = 0; idx < ACT_COUNT; idx = idx + 1) begin
            if (index_i == idx[INDEX_W-1:0]) begin
                act_o = act_vec_i[idx*DATA_W +: DATA_W];
            end
        end
    end

endmodule

`default_nettype wire
