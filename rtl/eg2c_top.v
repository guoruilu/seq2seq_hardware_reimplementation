`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_top #(
    parameter integer DATA_W        = `EG2C_DATA_W,
    parameter integer WEIGHT_W      = `EG2C_WEIGHT_W,
    parameter integer INDEX_W       = `EG2C_INDEX_W,
    parameter integer ACC_W         = `EG2C_ACC_W,
    parameter integer INSTR_W       = `EG2C_INSTR_W,
    parameter integer LANES         = `EG2C_LANE_COUNT,
    parameter integer ACT_ADDR_W    = `EG2C_ACT_ADDR_W,
    parameter integer ACT_DEPTH     = `EG2C_ACT_DEPTH,
    parameter integer WEIGHT_ADDR_W = `EG2C_WEIGHT_ADDR_W,
    parameter integer WEIGHT_DEPTH  = `EG2C_WEIGHT_DEPTH,
    parameter integer INDEX_ADDR_W  = `EG2C_INDEX_ADDR_W,
    parameter integer INDEX_DEPTH   = `EG2C_INDEX_DEPTH,
    parameter integer INSTR_ADDR_W  = `EG2C_INSTR_ADDR_W,
    parameter integer INSTR_DEPTH   = `EG2C_INSTR_DEPTH
) (
    input  wire                       clk_i,
    input  wire                       rst_ni,
    input  wire                       start_i,
    output wire                       busy_o,
    output wire                       done_o,
    output wire                       error_o,
    output wire [2:0]                 ctrl_state_o,
    output wire [7:0]                 ctrl_opcode_o,

    input  wire                       dbg_instr_we_i,
    input  wire [INSTR_ADDR_W-1:0]    dbg_instr_addr_i,
    input  wire [INSTR_W-1:0]         dbg_instr_wdata_i,
    output wire [INSTR_W-1:0]         dbg_instr_rdata_o,

    input  wire                       dbg_act0_we_i,
    input  wire [ACT_ADDR_W-1:0]      dbg_act0_addr_i,
    input  wire [DATA_W-1:0]          dbg_act0_wdata_i,
    output wire [DATA_W-1:0]          dbg_act0_rdata_o,

    input  wire                       dbg_act1_we_i,
    input  wire [ACT_ADDR_W-1:0]      dbg_act1_addr_i,
    input  wire [DATA_W-1:0]          dbg_act1_wdata_i,
    output wire [DATA_W-1:0]          dbg_act1_rdata_o,

    input  wire                       dbg_weight_we_i,
    input  wire [WEIGHT_ADDR_W-1:0]   dbg_weight_addr_i,
    input  wire [WEIGHT_W-1:0]        dbg_weight_wdata_i,
    output wire [WEIGHT_W-1:0]        dbg_weight_rdata_o,

    input  wire                       dbg_index_we_i,
    input  wire [INDEX_ADDR_W-1:0]    dbg_index_addr_i,
    input  wire [INDEX_W-1:0]         dbg_index_wdata_i,
    output wire [INDEX_W-1:0]         dbg_index_rdata_o
);

    localparam integer MAC_ACT_VEC_W    = LANES * DATA_W;
    localparam integer MAC_WEIGHT_VEC_W = LANES * WEIGHT_W;
    localparam integer MAC_ACC_VEC_W    = LANES * ACC_W;

    wire [INSTR_ADDR_W-1:0] ctrl_instr_addr;
    wire [INSTR_W-1:0]      instr_data;
    wire [INSTR_ADDR_W-1:0] instr_rd_addr;
    wire                    ctrl_busy;
    wire                    ctrl_done;

    wire                    input_buf_valid;
    wire [DATA_W-1:0]       input_buf_data;
    wire                    output_buf_valid;
    wire [DATA_W-1:0]       output_buf_data;

    wire [MAC_ACT_VEC_W-1:0]    mac_act_vec;
    wire [MAC_WEIGHT_VEC_W-1:0] mac_weight_vec;
    wire [MAC_ACC_VEC_W-1:0]    mac_acc_vec;
    wire [LANES-1:0]            mac_valid_vec;

    assign busy_o             = ctrl_busy;
    assign done_o             = ctrl_done;
    assign instr_rd_addr      = ctrl_busy ? ctrl_instr_addr : dbg_instr_addr_i;
    assign dbg_instr_rdata_o  = instr_data;
    assign mac_act_vec        = {MAC_ACT_VEC_W{1'b0}};
    assign mac_weight_vec     = {MAC_WEIGHT_VEC_W{1'b0}};

    eg2c_instr_mem #(
        .DATA_W(INSTR_W),
        .ADDR_W(INSTR_ADDR_W),
        .DEPTH(INSTR_DEPTH)
    ) u_instr_mem (
        .clk_i(clk_i),
        .we_i(dbg_instr_we_i),
        .wr_addr_i(dbg_instr_addr_i),
        .wr_data_i(dbg_instr_wdata_i),
        .rd_addr_i(instr_rd_addr),
        .rd_data_o(instr_data)
    );

    eg2c_act_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(ACT_ADDR_W),
        .DEPTH(ACT_DEPTH)
    ) u_act_gb0 (
        .clk_i(clk_i),
        .we_i(dbg_act0_we_i),
        .wr_addr_i(dbg_act0_addr_i),
        .wr_data_i(dbg_act0_wdata_i),
        .rd_addr_i(dbg_act0_addr_i),
        .rd_data_o(dbg_act0_rdata_o)
    );

    eg2c_act_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(ACT_ADDR_W),
        .DEPTH(ACT_DEPTH)
    ) u_act_gb1 (
        .clk_i(clk_i),
        .we_i(dbg_act1_we_i),
        .wr_addr_i(dbg_act1_addr_i),
        .wr_data_i(dbg_act1_wdata_i),
        .rd_addr_i(dbg_act1_addr_i),
        .rd_data_o(dbg_act1_rdata_o)
    );

    eg2c_weight_mem #(
        .DATA_W(WEIGHT_W),
        .ADDR_W(WEIGHT_ADDR_W),
        .DEPTH(WEIGHT_DEPTH)
    ) u_weight_mem (
        .clk_i(clk_i),
        .we_i(dbg_weight_we_i),
        .wr_addr_i(dbg_weight_addr_i),
        .wr_data_i(dbg_weight_wdata_i),
        .rd_addr_i(dbg_weight_addr_i),
        .rd_data_o(dbg_weight_rdata_o)
    );

    eg2c_index_mem #(
        .DATA_W(INDEX_W),
        .ADDR_W(INDEX_ADDR_W),
        .DEPTH(INDEX_DEPTH)
    ) u_index_mem (
        .clk_i(clk_i),
        .we_i(dbg_index_we_i),
        .wr_addr_i(dbg_index_addr_i),
        .wr_data_i(dbg_index_wdata_i),
        .rd_addr_i(dbg_index_addr_i),
        .rd_data_o(dbg_index_rdata_o)
    );

    eg2c_input_act_buffer #(
        .DATA_W(DATA_W)
    ) u_input_act_buffer (
        .valid_i(1'b0),
        .data_i(dbg_act0_rdata_o),
        .valid_o(input_buf_valid),
        .data_o(input_buf_data)
    );

    eg2c_output_act_buffer #(
        .DATA_W(DATA_W)
    ) u_output_act_buffer (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .valid_i(input_buf_valid),
        .data_i(input_buf_data),
        .valid_o(output_buf_valid),
        .data_o(output_buf_data)
    );

    eg2c_mac_array #(
        .LANES(LANES),
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .ACC_W(ACC_W)
    ) u_mac_array (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .clear_i(1'b0),
        .valid_i(1'b0),
        .act_vec_i(mac_act_vec),
        .weight_vec_i(mac_weight_vec),
        .acc_vec_o(mac_acc_vec),
        .valid_vec_o(mac_valid_vec)
    );

    eg2c_controller #(
        .INSTR_W(INSTR_W),
        .INSTR_ADDR_W(INSTR_ADDR_W),
        .INSTR_COUNT(INSTR_DEPTH)
    ) u_controller (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(start_i),
        .instr_data_i(instr_data),
        .instr_addr_o(ctrl_instr_addr),
        .busy_o(ctrl_busy),
        .done_o(ctrl_done),
        .error_o(error_o),
        .state_o(ctrl_state_o),
        .opcode_o(ctrl_opcode_o)
    );

endmodule

`default_nettype wire
