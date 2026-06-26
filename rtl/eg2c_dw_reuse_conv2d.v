`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module eg2c_dw_reuse_conv2d #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer ACC_W = `EG2C_ACC_W,
    parameter integer IN_H = 4,
    parameter integer IN_W = 4,
    parameter integer CHANNELS = 4,
    parameter integer K_H = 3,
    parameter integer K_W = 3,
    parameter integer PAD_H = 1,
    parameter integer PAD_W = 1
) (
    input  wire                                  clk_i,
    input  wire                                  rst_ni,
    input  wire                                  start_i,
    input  wire [IN_H*IN_W*CHANNELS*DATA_W-1:0] input_act_i,
    input  wire [K_H*K_W*CHANNELS*WEIGHT_W-1:0] weight_i,
    output wire [IN_H*IN_W*CHANNELS*DATA_W-1:0] output_act_o,
    output wire [IN_H*IN_W*CHANNELS*DATA_W-1:0] cir_output_act_o,
    output wire [IN_H*IN_W*CHANNELS*DATA_W-1:0] drir_output_act_o,
    output wire                                  busy_o,
    output reg                                   done_o,
    output wire [31:0]                           simple_cycle_count_o,
    output wire [31:0]                           cir_cycle_count_o,
    output wire [31:0]                           drir_cycle_count_o,
    output wire [31:0]                           simple_active_lane_count_o,
    output wire [31:0]                           cir_active_lane_count_o,
    output wire [31:0]                           drir_active_lane_count_o,
    output wire [31:0]                           simple_idle_lane_count_o,
    output wire [31:0]                           cir_idle_lane_count_o,
    output wire [31:0]                           drir_idle_lane_count_o,
    output wire                                  simple_trace_valid_o,
    output wire                                  cir_trace_valid_o,
    output wire                                  drir_trace_valid_o,
    output wire [31:0]                           simple_trace_o,
    output wire [31:0]                           cir_trace_o,
    output wire [31:0]                           drir_trace_o
);

    localparam integer MODE_SIMPLE = 0;
    localparam integer MODE_CIR    = 1;
    localparam integer MODE_DRIR   = 2;

    wire simple_busy;
    wire cir_busy;
    wire drir_busy;
    wire simple_done;
    wire cir_done;
    wire drir_done;

    reg simple_done_seen_q;
    reg cir_done_seen_q;
    reg drir_done_seen_q;
    reg op_active_q;
    reg start_d_q;

    wire child_start_pulse = start_i && !start_d_q && !op_active_q;

    assign busy_o = op_active_q;

    eg2c_dw_reuse_schedule #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .ACC_W(ACC_W),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .CHANNELS(CHANNELS),
        .K_H(K_H),
        .K_W(K_W),
        .PAD_H(PAD_H),
        .PAD_W(PAD_W),
        .MODE(MODE_SIMPLE)
    ) u_simple_schedule (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(child_start_pulse),
        .input_act_i(input_act_i),
        .weight_i(weight_i),
        .output_act_o(output_act_o),
        .busy_o(simple_busy),
        .done_o(simple_done),
        .cycle_count_o(simple_cycle_count_o),
        .active_lane_count_o(simple_active_lane_count_o),
        .idle_lane_count_o(simple_idle_lane_count_o),
        .trace_valid_o(simple_trace_valid_o),
        .trace_o(simple_trace_o)
    );

    eg2c_dw_reuse_schedule #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .ACC_W(ACC_W),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .CHANNELS(CHANNELS),
        .K_H(K_H),
        .K_W(K_W),
        .PAD_H(PAD_H),
        .PAD_W(PAD_W),
        .MODE(MODE_CIR)
    ) u_cir_schedule (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(child_start_pulse),
        .input_act_i(input_act_i),
        .weight_i(weight_i),
        .output_act_o(cir_output_act_o),
        .busy_o(cir_busy),
        .done_o(cir_done),
        .cycle_count_o(cir_cycle_count_o),
        .active_lane_count_o(cir_active_lane_count_o),
        .idle_lane_count_o(cir_idle_lane_count_o),
        .trace_valid_o(cir_trace_valid_o),
        .trace_o(cir_trace_o)
    );

    eg2c_dw_reuse_schedule #(
        .DATA_W(DATA_W),
        .WEIGHT_W(WEIGHT_W),
        .ACC_W(ACC_W),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .CHANNELS(CHANNELS),
        .K_H(K_H),
        .K_W(K_W),
        .PAD_H(PAD_H),
        .PAD_W(PAD_W),
        .MODE(MODE_DRIR)
    ) u_drir_schedule (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(child_start_pulse),
        .input_act_i(input_act_i),
        .weight_i(weight_i),
        .output_act_o(drir_output_act_o),
        .busy_o(drir_busy),
        .done_o(drir_done),
        .cycle_count_o(drir_cycle_count_o),
        .active_lane_count_o(drir_active_lane_count_o),
        .idle_lane_count_o(drir_idle_lane_count_o),
        .trace_valid_o(drir_trace_valid_o),
        .trace_o(drir_trace_o)
    );

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            simple_done_seen_q <= 1'b0;
            cir_done_seen_q    <= 1'b0;
            drir_done_seen_q   <= 1'b0;
            op_active_q        <= 1'b0;
            start_d_q          <= 1'b0;
            done_o             <= 1'b0;
        end else begin
            start_d_q <= start_i;
            done_o <= 1'b0;

            if (child_start_pulse) begin
                simple_done_seen_q <= 1'b0;
                cir_done_seen_q    <= 1'b0;
                drir_done_seen_q   <= 1'b0;
                op_active_q        <= 1'b1;
            end else begin
                if (simple_done) begin
                    simple_done_seen_q <= 1'b1;
                end
                if (cir_done) begin
                    cir_done_seen_q <= 1'b1;
                end
                if (drir_done) begin
                    drir_done_seen_q <= 1'b1;
                end

                if (op_active_q &&
                    (simple_done_seen_q || simple_done) &&
                    (cir_done_seen_q || cir_done) &&
                    (drir_done_seen_q || drir_done)) begin
                    done_o      <= 1'b1;
                    op_active_q <= 1'b0;
                end
            end
        end
    end

endmodule

module eg2c_dw_reuse_schedule #(
    parameter integer DATA_W = `EG2C_DATA_W,
    parameter integer WEIGHT_W = `EG2C_WEIGHT_W,
    parameter integer ACC_W = `EG2C_ACC_W,
    parameter integer IN_H = 4,
    parameter integer IN_W = 4,
    parameter integer CHANNELS = 4,
    parameter integer K_H = 3,
    parameter integer K_W = 3,
    parameter integer PAD_H = 1,
    parameter integer PAD_W = 1,
    parameter integer MODE = 0
) (
    input  wire                                  clk_i,
    input  wire                                  rst_ni,
    input  wire                                  start_i,
    input  wire [IN_H*IN_W*CHANNELS*DATA_W-1:0] input_act_i,
    input  wire [K_H*K_W*CHANNELS*WEIGHT_W-1:0] weight_i,
    output reg  [IN_H*IN_W*CHANNELS*DATA_W-1:0] output_act_o,
    output reg                                   busy_o,
    output reg                                   done_o,
    output reg  [31:0]                           cycle_count_o,
    output reg  [31:0]                           active_lane_count_o,
    output reg  [31:0]                           idle_lane_count_o,
    output reg                                   trace_valid_o,
    output reg  [31:0]                           trace_o
);

    localparam integer STATE_IDLE     = 2'd0;
    localparam integer STATE_CALC     = 2'd1;
    localparam integer STATE_FINALIZE = 2'd2;

    localparam integer MODE_SIMPLE = 0;
    localparam integer MODE_CIR    = 1;
    localparam integer MODE_DRIR   = 2;

    localparam integer OUTPUT_COUNT = IN_H * IN_W * CHANNELS;
    localparam integer ACC_TERMS = K_H * K_W;
    localparam integer ACC_REQ_W = DATA_W + WEIGHT_W + ((ACC_TERMS > 1) ? $clog2(ACC_TERMS) : 0);
    localparam integer PRODUCT_W = DATA_W + WEIGHT_W;
    localparam integer PAIR_COUNT = (IN_W + 1) / 2;
    localparam integer SIMPLE_CYCLES = IN_H * IN_W * CHANNELS * K_H * K_W;
    localparam integer CIR_CYCLES = IN_H * IN_W * CHANNELS * K_W;
    localparam integer DRIR_CYCLES = IN_H * CHANNELS * K_H * K_W * PAIR_COUNT;
    localparam integer SELECTED_CYCLES =
        (MODE == MODE_SIMPLE) ? SIMPLE_CYCLES :
        (MODE == MODE_CIR)    ? CIR_CYCLES :
                                DRIR_CYCLES;

    reg [1:0] state_q;
    integer cycle_index_q;
    reg signed [ACC_W-1:0] accum_mem [0:OUTPUT_COUNT-1];

    integer idx;
    integer tmp_idx;
    integer out_y;
    integer out_x;
    integer in_y;
    integer in_x;
    integer channel;
    integer ker_y;
    integer ker_x;
    integer pair_idx;
    integer lane_idx;
    integer output_index;
    integer active_lanes;
    integer idle_lanes;
    reg [31:0] trace_value;

    function signed [DATA_W-1:0] get_act;
        input integer y;
        input integer x;
        input integer c;
        integer flat_index;
        begin
            flat_index = ((y * IN_W + x) * CHANNELS + c) * DATA_W;
            get_act = input_act_i[flat_index +: DATA_W];
        end
    endfunction

    function signed [WEIGHT_W-1:0] get_weight;
        input integer ky;
        input integer kx;
        input integer c;
        integer flat_index;
        begin
            flat_index = ((ky * K_W + kx) * CHANNELS + c) * WEIGHT_W;
            get_weight = weight_i[flat_index +: WEIGHT_W];
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

    function [3:0] encode_coord4;
        input integer value;
        begin
            if (value < -8) begin
                encode_coord4 = 4'h0;
            end else if (value > 7) begin
                encode_coord4 = 4'hf;
            end else begin
                encode_coord4 = (value + 8) & 4'hf;
            end
        end
    endfunction

    function [3:0] encode_unsigned4;
        input integer value;
        begin
            if (value < 0) begin
                encode_unsigned4 = 4'hf;
            end else if (value > 14) begin
                encode_unsigned4 = 4'he;
            end else begin
                encode_unsigned4 = value[3:0];
            end
        end
    endfunction

    function [31:0] make_trace_descriptor;
        input integer term_lane;
        input integer term_out_y;
        input integer term_out_x;
        input integer term_channel;
        input integer term_ker_y;
        input integer term_ker_x;
        input term_active;
        begin
            make_trace_descriptor = {
                4'h0,
                encode_unsigned4(term_lane),
                encode_coord4(term_out_y),
                encode_coord4(term_out_x),
                encode_unsigned4(term_channel),
                encode_unsigned4(term_ker_y),
                encode_unsigned4(term_ker_x),
                3'b000,
                term_active
            };
        end
    endfunction

    function [31:0] mix_trace_value;
        input [31:0] current_value;
        input [31:0] descriptor;
        begin
            mix_trace_value = {current_value[26:0], current_value[31:27]} ^ descriptor;
        end
    endfunction

    task update_trace;
        input integer term_lane;
        input integer term_out_y;
        input integer term_out_x;
        input integer term_channel;
        input integer term_ker_y;
        input integer term_ker_x;
        input term_active;
        begin
            trace_value = mix_trace_value(
                trace_value,
                make_trace_descriptor(
                    term_lane,
                    term_out_y,
                    term_out_x,
                    term_channel,
                    term_ker_y,
                    term_ker_x,
                    term_active
                )
            );
        end
    endtask

    task accumulate_output_term;
        input integer term_lane;
        input integer term_out_y;
        input integer term_out_x;
        input integer term_channel;
        input integer term_ker_y;
        input integer term_ker_x;
        integer local_in_y;
        integer local_in_x;
        integer local_output_index;
        reg signed [DATA_W-1:0] act_value;
        reg signed [WEIGHT_W-1:0] weight_value;
        reg signed [PRODUCT_W-1:0] product_value;
        reg signed [ACC_W-1:0] product_ext;
        reg lane_active;
        begin
            lane_active = 1'b0;
            if (term_out_y >= 0 && term_out_y < IN_H &&
                term_out_x >= 0 && term_out_x < IN_W &&
                term_channel >= 0 && term_channel < CHANNELS &&
                term_ker_y >= 0 && term_ker_y < K_H &&
                term_ker_x >= 0 && term_ker_x < K_W) begin
                local_in_y = term_out_y + term_ker_y - PAD_H;
                local_in_x = term_out_x + term_ker_x - PAD_W;
                if (local_in_y >= 0 && local_in_y < IN_H && local_in_x >= 0 && local_in_x < IN_W) begin
                    lane_active = 1'b1;
                    active_lanes = active_lanes + 1;
                    local_output_index = (term_out_y * IN_W + term_out_x) * CHANNELS + term_channel;
                    act_value = get_act(local_in_y, local_in_x, term_channel);
                    weight_value = get_weight(term_ker_y, term_ker_x, term_channel);
                    product_value = act_value * weight_value;
                    product_ext = {{(ACC_W-PRODUCT_W){product_value[PRODUCT_W-1]}}, product_value};
                    accum_mem[local_output_index] = accum_mem[local_output_index] + product_ext;
                end else begin
                    idle_lanes = idle_lanes + 1;
                end
            end else begin
                idle_lanes = idle_lanes + 1;
            end
            update_trace(term_lane, term_out_y, term_out_x, term_channel, term_ker_y, term_ker_x, lane_active);
        end
    endtask

    initial begin
        if (DATA_W != 8 || WEIGHT_W != 8) begin
            $fatal(1, "eg2c_dw_reuse_schedule currently requires 8-bit activations and weights");
        end
        if (ACC_W < ACC_REQ_W || ACC_W < PRODUCT_W) begin
            $fatal(1, "eg2c_dw_reuse_schedule ACC_W is too small for the full kernel accumulation");
        end
        if (IN_H <= 0 || IN_W <= 0 || CHANNELS <= 0 || K_H <= 0 || K_W <= 0) begin
            $fatal(1, "eg2c_dw_reuse_schedule dimensions must be positive");
        end
        if (MODE < MODE_SIMPLE || MODE > MODE_DRIR) begin
            $fatal(1, "eg2c_dw_reuse_schedule MODE must be simple, CIR, or D-RIR");
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q             <= STATE_IDLE;
            cycle_index_q       <= 0;
            output_act_o        <= {(OUTPUT_COUNT*DATA_W){1'b0}};
            busy_o              <= 1'b0;
            done_o              <= 1'b0;
            cycle_count_o       <= 32'd0;
            active_lane_count_o <= 32'd0;
            idle_lane_count_o   <= 32'd0;
            trace_valid_o       <= 1'b0;
            trace_o             <= 32'd0;
            for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                accum_mem[idx] <= {ACC_W{1'b0}};
            end
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    busy_o <= 1'b0;
                    trace_valid_o <= 1'b0;
                    if (start_i) begin
                        cycle_index_q       <= 0;
                        output_act_o        <= {(OUTPUT_COUNT*DATA_W){1'b0}};
                        cycle_count_o       <= 32'd0;
                        active_lane_count_o <= 32'd0;
                        idle_lane_count_o   <= 32'd0;
                        trace_o             <= 32'd0;
                        for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                            accum_mem[idx] <= {ACC_W{1'b0}};
                        end
                        busy_o  <= 1'b1;
                        state_q <= STATE_CALC;
                    end
                end

                STATE_CALC: begin
                    active_lanes = 0;
                    idle_lanes = 0;
                    trace_value = 32'h9e3779b9 ^ cycle_index_q[31:0];

                    if (MODE == MODE_SIMPLE) begin
                        tmp_idx = cycle_index_q;
                        ker_x = tmp_idx % K_W;
                        tmp_idx = tmp_idx / K_W;
                        ker_y = tmp_idx % K_H;
                        tmp_idx = tmp_idx / K_H;
                        channel = tmp_idx % CHANNELS;
                        tmp_idx = tmp_idx / CHANNELS;
                        out_x = tmp_idx % IN_W;
                        tmp_idx = tmp_idx / IN_W;
                        out_y = tmp_idx;
                        accumulate_output_term(0, out_y, out_x, channel, ker_y, ker_x);
                    end else if (MODE == MODE_CIR) begin
                        tmp_idx = cycle_index_q;
                        ker_x = tmp_idx % K_W;
                        tmp_idx = tmp_idx / K_W;
                        channel = tmp_idx % CHANNELS;
                        tmp_idx = tmp_idx / CHANNELS;
                        in_x = tmp_idx % IN_W;
                        tmp_idx = tmp_idx / IN_W;
                        in_y = tmp_idx;
                        for (lane_idx = 0; lane_idx < K_H; lane_idx = lane_idx + 1) begin
                            ker_y = lane_idx;
                            out_y = in_y - ker_y + PAD_H;
                            out_x = in_x - ker_x + PAD_W;
                            accumulate_output_term(lane_idx, out_y, out_x, channel, ker_y, ker_x);
                        end
                    end else begin
                        tmp_idx = cycle_index_q;
                        pair_idx = tmp_idx % PAIR_COUNT;
                        tmp_idx = tmp_idx / PAIR_COUNT;
                        ker_x = tmp_idx % K_W;
                        tmp_idx = tmp_idx / K_W;
                        ker_y = tmp_idx % K_H;
                        tmp_idx = tmp_idx / K_H;
                        channel = tmp_idx % CHANNELS;
                        tmp_idx = tmp_idx / CHANNELS;
                        out_y = tmp_idx;
                        for (lane_idx = 0; lane_idx < 2; lane_idx = lane_idx + 1) begin
                            out_x = pair_idx * 2 + lane_idx;
                            accumulate_output_term(lane_idx, out_y, out_x, channel, ker_y, ker_x);
                        end
                    end

                    cycle_count_o       <= cycle_count_o + 32'd1;
                    active_lane_count_o <= active_lane_count_o + active_lanes[31:0];
                    idle_lane_count_o   <= idle_lane_count_o + idle_lanes[31:0];
                    trace_valid_o       <= 1'b1;
                    trace_o             <= trace_value;

                    if (cycle_index_q == SELECTED_CYCLES - 1) begin
                        state_q <= STATE_FINALIZE;
                    end else begin
                        cycle_index_q <= cycle_index_q + 1;
                    end
                end

                STATE_FINALIZE: begin
                    trace_valid_o <= 1'b0;
                    for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                        output_act_o[idx*DATA_W +: DATA_W] <= saturate_int8(accum_mem[idx]);
                    end
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    state_q <= STATE_IDLE;
                end

                default: begin
                    state_q       <= STATE_IDLE;
                    busy_o        <= 1'b0;
                    trace_valid_o <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
