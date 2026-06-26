`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_controller #(
    parameter integer INSTR_W      = `EG2C_INSTR_W,
    parameter integer INSTR_ADDR_W = `EG2C_INSTR_ADDR_W,
    parameter integer INSTR_COUNT  = `EG2C_INSTR_DEPTH
) (
    input  wire                    clk_i,
    input  wire                    rst_ni,
    input  wire                    start_i,
    input  wire [INSTR_W-1:0]      instr_data_i,
    output reg  [INSTR_ADDR_W-1:0] instr_addr_o,
    output reg                     busy_o,
    output reg                     done_o,
    output reg                     error_o,
    output reg  [2:0]              state_o,
    output wire [7:0]              opcode_o
);

    assign opcode_o = instr_data_i[31:24];

    initial begin
        if (INSTR_COUNT < 1 || INSTR_COUNT > (2 ** INSTR_ADDR_W)) begin
            $fatal(1, "eg2c_controller INSTR_COUNT must fit within INSTR_ADDR_W");
        end
    end

    function valid_opcode;
        input [7:0] opcode;
        begin
            valid_opcode = (opcode == `EG2C_OP_CONV) ||
                           (opcode == `EG2C_OP_DW) ||
                           (opcode == `EG2C_OP_PW) ||
                           (opcode == `EG2C_OP_POOL) ||
                           (opcode == `EG2C_OP_THRESHOLD);
        end
    endfunction

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            instr_addr_o <= {INSTR_ADDR_W{1'b0}};
            busy_o       <= 1'b0;
            done_o       <= 1'b0;
            error_o      <= 1'b0;
            state_o      <= `EG2C_CTRL_IDLE;
        end else begin
            done_o <= 1'b0;

            case (state_o)
                `EG2C_CTRL_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        instr_addr_o <= {INSTR_ADDR_W{1'b0}};
                        busy_o       <= 1'b1;
                        error_o      <= 1'b0;
                        state_o      <= `EG2C_CTRL_FETCH;
                    end
                end

                `EG2C_CTRL_FETCH: begin
                    if (instr_addr_o >= INSTR_COUNT) begin
                        error_o <= 1'b1;
                        state_o <= `EG2C_CTRL_DONE;
                    end else begin
                        state_o <= `EG2C_CTRL_DECODE;
                    end
                end

                `EG2C_CTRL_DECODE: begin
                    if (opcode_o == `EG2C_OP_DONE) begin
                        state_o <= `EG2C_CTRL_DONE;
                    end else if (opcode_o == `EG2C_OP_NOP) begin
                        if (instr_addr_o >= INSTR_COUNT - 1) begin
                            error_o <= 1'b1;
                            state_o <= `EG2C_CTRL_DONE;
                        end else begin
                            instr_addr_o <= instr_addr_o + {{(INSTR_ADDR_W-1){1'b0}}, 1'b1};
                            state_o      <= `EG2C_CTRL_FETCH;
                        end
                    end else if (valid_opcode(opcode_o)) begin
                        // This controller is still a top-level smoke scheduler.
                        // Operation-specific layer execution is modeled by
                        // eg2c_dense_pipeline and later integrated top work.
                        state_o     <= `EG2C_CTRL_RUN;
                    end else begin
                        error_o <= 1'b1;
                        state_o <= `EG2C_CTRL_DONE;
                    end
                end

                `EG2C_CTRL_RUN: begin
                    if (instr_addr_o >= INSTR_COUNT - 1) begin
                        error_o <= 1'b1;
                        state_o <= `EG2C_CTRL_DONE;
                    end else begin
                        instr_addr_o <= instr_addr_o + {{(INSTR_ADDR_W-1){1'b0}}, 1'b1};
                        state_o      <= `EG2C_CTRL_FETCH;
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
