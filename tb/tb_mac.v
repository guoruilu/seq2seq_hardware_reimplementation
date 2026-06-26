`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_mac;

    reg clk;
    reg rst_n;
    reg clear;
    reg valid;
    reg signed [`EG2C_DATA_W-1:0] lane_act;
    reg signed [`EG2C_WEIGHT_W-1:0] lane_weight;
    wire signed [`EG2C_ACC_W-1:0] lane_acc;
    wire lane_valid;

    reg [(`EG2C_LANE_COUNT*`EG2C_DATA_W)-1:0] act_vec;
    reg [(`EG2C_LANE_COUNT*`EG2C_WEIGHT_W)-1:0] weight_vec;
    wire [(`EG2C_LANE_COUNT*`EG2C_ACC_W)-1:0] acc_vec;
    wire [`EG2C_LANE_COUNT-1:0] valid_vec;

    integer mismatches;
    integer lane_idx;
    reg signed [`EG2C_ACC_W-1:0] got_acc;
    reg signed [`EG2C_ACC_W-1:0] expected_acc;

    eg2c_mac_lane u_lane (
        .clk_i(clk),
        .rst_ni(rst_n),
        .clear_i(clear),
        .valid_i(valid),
        .act_i(lane_act),
        .weight_i(lane_weight),
        .acc_o(lane_acc),
        .valid_o(lane_valid)
    );

    eg2c_mac_array u_array (
        .clk_i(clk),
        .rst_ni(rst_n),
        .clear_i(clear),
        .valid_i(valid),
        .act_vec_i(act_vec),
        .weight_vec_i(weight_vec),
        .acc_vec_o(acc_vec),
        .valid_vec_o(valid_vec)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/mac/wave.vcd");
            $dumpvars(0, tb_mac);
        end
    end

    initial begin
        mismatches = 0;
        clear = 1'b0;
        valid = 1'b0;
        lane_act = '0;
        lane_weight = '0;
        act_vec = '0;
        weight_vec = '0;
        rst_n = 1'b0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        drive_lane(8'sd3, -8'sd4);
        check_lane_acc(-32'sd12, 1'b1, "lane first signed product");

        drive_lane(-8'sd2, -8'sd5);
        check_lane_acc(-32'sd2, 1'b1, "lane accumulated product");

        @(negedge clk);
        valid = 1'b0;
        lane_act = 8'sd7;
        lane_weight = 8'sd9;
        @(posedge clk);
        #1;
        check_lane_acc(-32'sd2, 1'b0, "lane holds when invalid");

        @(negedge clk);
        clear = 1'b1;
        @(posedge clk);
        #1;
        clear = 1'b0;
        check_lane_acc(32'sd0, 1'b0, "lane clear");

        for (lane_idx = 0; lane_idx < `EG2C_LANE_COUNT; lane_idx = lane_idx + 1) begin
            act_vec[lane_idx*`EG2C_DATA_W +: `EG2C_DATA_W] = lane_idx[7:0] - 8'd16;
            weight_vec[lane_idx*`EG2C_WEIGHT_W +: `EG2C_WEIGHT_W] = 8'd3;
        end

        @(negedge clk);
        valid = 1'b1;
        lane_act = 8'sd1;
        lane_weight = 8'sd1;
        @(posedge clk);
        #1;
        valid = 1'b0;

        for (lane_idx = 0; lane_idx < `EG2C_LANE_COUNT; lane_idx = lane_idx + 1) begin
            got_acc = acc_vec[lane_idx*`EG2C_ACC_W +: `EG2C_ACC_W];
            expected_acc = $signed(lane_idx - 16) * 32'sd3;
            if (got_acc !== expected_acc) begin
                $display("ERROR: array lane %0d got=%0d expected=%0d", lane_idx, got_acc, expected_acc);
                mismatches = mismatches + 1;
            end
        end

        if (valid_vec !== {`EG2C_LANE_COUNT{1'b1}}) begin
            $display("ERROR: array valid_vec got=%h expected all ones", valid_vec);
            mismatches = mismatches + 1;
        end

        if (mismatches == 0) begin
            $display("target=mac mismatches=0 PASS");
            $finish;
        end else begin
            $display("target=mac mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

    task drive_lane;
        input signed [`EG2C_DATA_W-1:0] act;
        input signed [`EG2C_WEIGHT_W-1:0] weight;
        begin
            @(negedge clk);
            lane_act = act;
            lane_weight = weight;
            valid = 1'b1;
            @(posedge clk);
            #1;
            valid = 1'b0;
        end
    endtask

    task check_lane_acc;
        input signed [`EG2C_ACC_W-1:0] expected;
        input expected_valid;
        input [255:0] label;
        begin
            if (lane_acc !== expected) begin
                $display("ERROR: %0s acc got=%0d expected=%0d", label, lane_acc, expected);
                mismatches = mismatches + 1;
            end
            if (lane_valid !== expected_valid) begin
                $display("ERROR: %0s valid got=%0b expected=%0b", label, lane_valid, expected_valid);
                mismatches = mismatches + 1;
            end
        end
    endtask

endmodule

`default_nettype wire
