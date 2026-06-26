`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_sparse_vector_mac #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer INDEX_W = `EG2C_INDEX_W,
    parameter integer ACC_W = `EG2C_ACC_W,
    parameter integer ACT_COUNT = 16,
    parameter integer VEC_COUNT = 5,
    parameter integer VEC_LEN = 3
) (
    input  wire                                      clk_i,
    input  wire                                      rst_ni,
    input  wire                                      start_i,
    input  wire [ACT_COUNT*DATA_W-1:0]               act_vec_i,
    input  wire [VEC_COUNT*VEC_LEN*INDEX_W-1:0]      index_vec_i,
    input  wire [VEC_COUNT*VEC_LEN*WEIGHT_W-1:0]     weight_vec_i,
    input  wire [VEC_COUNT-1:0]                      vector_valid_i,
    output reg  [DATA_W-1:0]                         output_act_o,
    output reg  signed [ACC_W-1:0]                   output_acc_o,
    output reg                                       busy_o,
    output reg                                       done_o,
    output reg  [31:0]                               cycle_count_o,
    output reg  [31:0]                               active_cycle_count_o,
    output reg  [31:0]                               skipped_vector_count_o
);

    localparam integer STATE_IDLE = 2'd0;
    localparam integer STATE_RUN  = 2'd1;
    localparam integer STATE_DONE = 2'd2;

    reg [1:0] state_q;
    integer vec_q;
    integer elem_q;
    reg signed [ACC_W-1:0] acc_q;

    wire [DATA_W-1:0] selected_act;
    reg [INDEX_W-1:0] current_index;
    reg signed [WEIGHT_W-1:0] current_weight;
    reg signed [DATA_W-1:0] current_act;
    reg signed [DATA_W+WEIGHT_W-1:0] product_value;
    reg signed [ACC_W-1:0] acc_next;
    reg last_active_element;

    eg2c_sparse_selector #(
        .DATA_W(DATA_W),
        .INDEX_W(INDEX_W),
        .ACT_COUNT(ACT_COUNT)
    ) u_selector (
        .act_vec_i(act_vec_i),
        .index_i(current_index),
        .act_o(selected_act)
    );

    function [INDEX_W-1:0] get_index;
        input integer vec;
        input integer elem;
        integer flat_index;
        begin
            flat_index = (vec * VEC_LEN + elem) * INDEX_W;
            get_index = index_vec_i[flat_index +: INDEX_W];
        end
    endfunction

    function signed [WEIGHT_W-1:0] get_weight;
        input integer vec;
        input integer elem;
        integer flat_index;
        begin
            flat_index = (vec * VEC_LEN + elem) * WEIGHT_W;
            get_weight = weight_vec_i[flat_index +: WEIGHT_W];
        end
    endfunction

    function [DATA_W-1:0] saturate_int8;
        input signed [ACC_W-1:0] value;
        begin
            if (value > 32'sd127) begin
                saturate_int8 = 8'h7f;
            end else if (value < -32'sd128) begin
                saturate_int8 = 8'h80;
            end else begin
                saturate_int8 = value[DATA_W-1:0];
            end
        end
    endfunction

    always @(vec_q or elem_q or acc_q or selected_act or index_vec_i or weight_vec_i) begin
        current_index = get_index(vec_q, elem_q);
        current_weight = get_weight(vec_q, elem_q);
        current_act = selected_act;
        product_value = current_act * current_weight;
        acc_next = acc_q + {{(ACC_W-(DATA_W+WEIGHT_W)){product_value[DATA_W+WEIGHT_W-1]}}, product_value};
        last_active_element = (vec_q == VEC_COUNT - 1) && (elem_q == VEC_LEN - 1);
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q                <= STATE_IDLE;
            vec_q                  <= 0;
            elem_q                 <= 0;
            acc_q                  <= {ACC_W{1'b0}};
            output_act_o           <= {DATA_W{1'b0}};
            output_acc_o           <= {ACC_W{1'b0}};
            busy_o                 <= 1'b0;
            done_o                 <= 1'b0;
            cycle_count_o          <= 32'd0;
            active_cycle_count_o   <= 32'd0;
            skipped_vector_count_o <= 32'd0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        vec_q                  <= 0;
                        elem_q                 <= 0;
                        acc_q                  <= {ACC_W{1'b0}};
                        output_act_o           <= {DATA_W{1'b0}};
                        output_acc_o           <= {ACC_W{1'b0}};
                        cycle_count_o          <= 32'd0;
                        active_cycle_count_o   <= 32'd0;
                        skipped_vector_count_o <= 32'd0;
                        busy_o                 <= 1'b1;
                        state_q                <= STATE_RUN;
                    end
                end

                STATE_RUN: begin
                    cycle_count_o <= cycle_count_o + 32'd1;

                    if (!vector_valid_i[vec_q]) begin
                        skipped_vector_count_o <= skipped_vector_count_o + 32'd1;
                        elem_q <= 0;
                        if (vec_q == VEC_COUNT - 1) begin
                            output_acc_o <= acc_q;
                            output_act_o <= saturate_int8(acc_q);
                            state_q      <= STATE_DONE;
                        end else begin
                            vec_q <= vec_q + 1;
                        end
                    end else begin
                        active_cycle_count_o <= active_cycle_count_o + 32'd1;
                        acc_q <= acc_next;

                        if (last_active_element) begin
                            output_acc_o <= acc_next;
                            output_act_o <= saturate_int8(acc_next);
                            state_q      <= STATE_DONE;
                        end else if (elem_q == VEC_LEN - 1) begin
                            elem_q <= 0;
                            vec_q  <= vec_q + 1;
                        end else begin
                            elem_q <= elem_q + 1;
                        end
                    end
                end

                STATE_DONE: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    state_q <= STATE_IDLE;
                end

                default: begin
                    busy_o  <= 1'b0;
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
