`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_controller #(
    parameter integer INSTR_W      = `EG2C_INSTR_W,
    parameter integer INSTR_ADDR_W = `EG2C_INSTR_ADDR_W
) (
    input  wire                    clk_i,
    input  wire                    rst_ni,
    input  wire                    start_i,
    input  wire [INSTR_W-1:0]      instr_data_i,
    output reg  [INSTR_ADDR_W-1:0] instr_addr_o,
    output reg                     busy_o,
    output reg                     done_o,
    output reg  [2:0]              state_o,
    output wire [7:0]              opcode_o
);

    reg [1:0] run_count_q;

    assign opcode_o = instr_data_i[31:24];

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            instr_addr_o <= {INSTR_ADDR_W{1'b0}};
            busy_o       <= 1'b0;
            done_o       <= 1'b0;
            state_o      <= `EG2C_CTRL_IDLE;
            run_count_q  <= 2'd0;
        end else begin
            done_o <= 1'b0;

            case (state_o)
                `EG2C_CTRL_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        instr_addr_o <= {INSTR_ADDR_W{1'b0}};
                        busy_o       <= 1'b1;
                        state_o      <= `EG2C_CTRL_FETCH;
                    end
                end

                `EG2C_CTRL_FETCH: begin
                    state_o <= `EG2C_CTRL_DECODE;
                end

                `EG2C_CTRL_DECODE: begin
                    if (opcode_o == `EG2C_OP_DONE) begin
                        state_o <= `EG2C_CTRL_DONE;
                    end else begin
                        run_count_q <= 2'd2;
                        state_o     <= `EG2C_CTRL_RUN;
                    end
                end

                `EG2C_CTRL_RUN: begin
                    if (run_count_q == 2'd0) begin
                        state_o <= `EG2C_CTRL_DONE;
                    end else begin
                        run_count_q <= run_count_q - 2'd1;
                    end
                end

                `EG2C_CTRL_DONE: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    state_o <= `EG2C_CTRL_IDLE;
                end

                default: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b0;
                    state_o <= `EG2C_CTRL_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
