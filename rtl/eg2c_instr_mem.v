`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_instr_mem #(
    parameter integer DATA_W = `EG2C_INSTR_W,
    parameter integer ADDR_W = `EG2C_INSTR_ADDR_W,
    parameter integer DEPTH  = `EG2C_INSTR_DEPTH
) (
    input  wire                  clk_i,
    input  wire                  we_i,
    input  wire [ADDR_W-1:0]     wr_addr_i,
    input  wire [DATA_W-1:0]     wr_data_i,
    input  wire [ADDR_W-1:0]     rd_addr_i,
    output wire [DATA_W-1:0]     rd_data_o
);

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    assign rd_data_o = mem[rd_addr_i];

    always @(posedge clk_i) begin
        if (we_i) begin
            mem[wr_addr_i] <= wr_data_i;
        end
    end

endmodule

`default_nettype wire
