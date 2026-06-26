`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_dense_pipeline #(
    parameter integer DATA_W      = `EG2C_DATA_W,
    parameter integer WEIGHT_W    = `EG2C_WEIGHT_W,
    parameter integer INSTR_W     = `EG2C_INSTR_W,
    parameter integer INSTR_COUNT = 4,
    parameter integer IN_H        = 4,
    parameter integer IN_W        = 4,
    parameter integer IN_C        = 2,
    parameter integer CONV_OUT_C  = 3,
    parameter integer POOL_OUT_H  = 2,
    parameter integer POOL_OUT_W  = 2
) (
    input  wire                                                clk_i,
    input  wire                                                rst_ni,
    input  wire                                                start_i,
    input  wire [INSTR_COUNT*INSTR_W-1:0]                      instr_mem_i,
    input  wire [IN_H*IN_W*IN_C*DATA_W-1:0]                    input_act_i,
    input  wire [3*3*IN_C*CONV_OUT_C*WEIGHT_W-1:0]             conv_weight_i,
    output wire [POOL_OUT_H*POOL_OUT_W*CONV_OUT_C*DATA_W-1:0]  output_act_o,
    output reg                                                 busy_o,
    output reg                                                 done_o,
    output reg                                                 error_o,
    output reg  [31:0]                                         cycle_count_o,
    output reg  [7:0]                                          op_count_o
);

    localparam integer STATE_IDLE      = 3'd0;
    localparam integer STATE_FETCH     = 3'd1;
    localparam integer STATE_DECODE    = 3'd2;
    localparam integer STATE_WAIT_CONV = 3'd3;
    localparam integer STATE_WAIT_POOL = 3'd4;
    localparam integer STATE_DONE      = 3'd5;

    reg [2:0] state_q;
    integer pc_q;
    reg [INSTR_W-1:0] instr_q;
    reg conv_start_q;
    reg pool_start_q;

    wire [7:0] opcode;
    wire conv_busy;
    wire conv_done;
    wire [31:0] conv_cycle_count;
    wire [31:0] conv_active_cycle_count;
    wire [31:0] conv_skipped_vector_count;
    wire pool_busy;
    wire pool_done;
    wire [31:0] pool_cycle_count;
    wire [IN_H*IN_W*CONV_OUT_C*DATA_W-1:0] conv_output;
    localparam integer CONV_SPARSE_VEC_LEN = 3 * IN_C;
    localparam integer CONV_SPARSE_VEC_COUNT = (3 * 3 * IN_C + CONV_SPARSE_VEC_LEN - 1) / CONV_SPARSE_VEC_LEN;
    localparam integer CONV_SPARSE_VALID_COUNT = CONV_OUT_C * CONV_SPARSE_VEC_COUNT;

    assign opcode = instr_q[31:24];

    function [INSTR_W-1:0] get_instr;
        input integer pc;
        integer flat_index;
        begin
            flat_index = pc * INSTR_W;
            get_instr = instr_mem_i[flat_index +: INSTR_W];
        end
    endfunction

    eg2c_dense_conv2d #(
        .IN_H(IN_H),
        .IN_W(IN_W),
        .IN_C(IN_C),
        .OUT_C(CONV_OUT_C),
        .K_H(3),
        .K_W(3),
        .PAD_H(1),
        .PAD_W(1)
    ) u_conv (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(conv_start_q),
        .sparse_enable_i(1'b0),
        .input_act_i(input_act_i),
        .weight_i(conv_weight_i),
        .sparse_vector_valid_i({CONV_SPARSE_VALID_COUNT{1'b0}}),
        .output_act_o(conv_output),
        .busy_o(conv_busy),
        .done_o(conv_done),
        .cycle_count_o(conv_cycle_count),
        .active_cycle_count_o(conv_active_cycle_count),
        .skipped_vector_count_o(conv_skipped_vector_count)
    );

    eg2c_avg_pool2d #(
        .IN_H(IN_H),
        .IN_W(IN_W),
        .CHANNELS(CONV_OUT_C),
        .POOL_H(2),
        .POOL_W(2),
        .STRIDE_H(2),
        .STRIDE_W(2),
        .OUT_H(POOL_OUT_H),
        .OUT_W(POOL_OUT_W)
    ) u_pool (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(pool_start_q),
        .input_act_i(conv_output),
        .output_act_o(output_act_o),
        .busy_o(pool_busy),
        .done_o(pool_done),
        .cycle_count_o(pool_cycle_count)
    );

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= STATE_IDLE;
            pc_q          <= 0;
            instr_q       <= {INSTR_W{1'b0}};
            conv_start_q  <= 1'b0;
            pool_start_q  <= 1'b0;
            busy_o        <= 1'b0;
            done_o        <= 1'b0;
            error_o       <= 1'b0;
            cycle_count_o <= 32'd0;
            op_count_o    <= 8'd0;
        end else begin
            conv_start_q <= 1'b0;
            pool_start_q <= 1'b0;
            done_o       <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        pc_q          <= 0;
                        instr_q       <= {INSTR_W{1'b0}};
                        cycle_count_o <= 32'd0;
                        op_count_o    <= 8'd0;
                        error_o       <= 1'b0;
                        busy_o        <= 1'b1;
                        state_q       <= STATE_FETCH;
                    end
                end

                STATE_FETCH: begin
                    if (pc_q >= INSTR_COUNT) begin
                        error_o <= 1'b1;
                        state_q <= STATE_DONE;
                    end else begin
                        instr_q <= get_instr(pc_q);
                        state_q <= STATE_DECODE;
                    end
                end

                STATE_DECODE: begin
                    if (opcode == `EG2C_OP_CONV) begin
                        conv_start_q <= 1'b1;
                        state_q      <= STATE_WAIT_CONV;
                    end else if (opcode == `EG2C_OP_POOL) begin
                        pool_start_q <= 1'b1;
                        state_q      <= STATE_WAIT_POOL;
                    end else if (opcode == `EG2C_OP_DONE) begin
                        state_q <= STATE_DONE;
                    end else if (opcode == `EG2C_OP_NOP) begin
                        pc_q    <= pc_q + 1;
                        state_q <= STATE_FETCH;
                    end else begin
                        error_o <= 1'b1;
                        state_q <= STATE_DONE;
                    end
                end

                STATE_WAIT_CONV: begin
                    if (conv_done) begin
                        cycle_count_o <= cycle_count_o + conv_cycle_count;
                        op_count_o    <= op_count_o + 8'd1;
                        pc_q          <= pc_q + 1;
                        state_q       <= STATE_FETCH;
                    end
                end

                STATE_WAIT_POOL: begin
                    if (pool_done) begin
                        cycle_count_o <= cycle_count_o + pool_cycle_count;
                        op_count_o    <= op_count_o + 8'd1;
                        pc_q          <= pc_q + 1;
                        state_q       <= STATE_FETCH;
                    end
                end

                STATE_DONE: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    state_q <= STATE_IDLE;
                end

                default: begin
                    busy_o  <= 1'b0;
                    error_o <= 1'b1;
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
