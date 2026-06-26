`timescale 1ns/1ps
`default_nettype none

`include "eg2c_defines.vh"

module tb_smoke;

    reg clk;
    reg rst_n;
    reg start;

    wire busy;
    wire done;
    wire [2:0] ctrl_state;
    wire [7:0] ctrl_opcode;

    reg dbg_instr_we;
    reg [`EG2C_INSTR_ADDR_W-1:0] dbg_instr_addr;
    reg [`EG2C_INSTR_W-1:0] dbg_instr_wdata;
    wire [`EG2C_INSTR_W-1:0] dbg_instr_rdata;

    reg dbg_act0_we;
    reg [`EG2C_ACT_ADDR_W-1:0] dbg_act0_addr;
    reg [`EG2C_DATA_W-1:0] dbg_act0_wdata;
    wire [`EG2C_DATA_W-1:0] dbg_act0_rdata;

    reg dbg_act1_we;
    reg [`EG2C_ACT_ADDR_W-1:0] dbg_act1_addr;
    reg [`EG2C_DATA_W-1:0] dbg_act1_wdata;
    wire [`EG2C_DATA_W-1:0] dbg_act1_rdata;

    reg dbg_weight_we;
    reg [`EG2C_WEIGHT_ADDR_W-1:0] dbg_weight_addr;
    reg [`EG2C_WEIGHT_W-1:0] dbg_weight_wdata;
    wire [`EG2C_WEIGHT_W-1:0] dbg_weight_rdata;

    reg dbg_index_we;
    reg [`EG2C_INDEX_ADDR_W-1:0] dbg_index_addr;
    reg [`EG2C_INDEX_W-1:0] dbg_index_wdata;
    wire [`EG2C_INDEX_W-1:0] dbg_index_rdata;

    integer mismatches;
    integer cycles;

    eg2c_top dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .busy_o(busy),
        .done_o(done),
        .ctrl_state_o(ctrl_state),
        .ctrl_opcode_o(ctrl_opcode),
        .dbg_instr_we_i(dbg_instr_we),
        .dbg_instr_addr_i(dbg_instr_addr),
        .dbg_instr_wdata_i(dbg_instr_wdata),
        .dbg_instr_rdata_o(dbg_instr_rdata),
        .dbg_act0_we_i(dbg_act0_we),
        .dbg_act0_addr_i(dbg_act0_addr),
        .dbg_act0_wdata_i(dbg_act0_wdata),
        .dbg_act0_rdata_o(dbg_act0_rdata),
        .dbg_act1_we_i(dbg_act1_we),
        .dbg_act1_addr_i(dbg_act1_addr),
        .dbg_act1_wdata_i(dbg_act1_wdata),
        .dbg_act1_rdata_o(dbg_act1_rdata),
        .dbg_weight_we_i(dbg_weight_we),
        .dbg_weight_addr_i(dbg_weight_addr),
        .dbg_weight_wdata_i(dbg_weight_wdata),
        .dbg_weight_rdata_o(dbg_weight_rdata),
        .dbg_index_we_i(dbg_index_we),
        .dbg_index_addr_i(dbg_index_addr),
        .dbg_index_wdata_i(dbg_index_wdata),
        .dbg_index_rdata_o(dbg_index_rdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if ($test$plusargs("WAVE")) begin
            $dumpfile("sim/build/smoke/wave.vcd");
            $dumpvars(0, tb_smoke);
        end
    end

    initial begin
        mismatches = 0;
        rst_n = 1'b0;
        start = 1'b0;
        dbg_instr_we = 1'b0;
        dbg_instr_addr = {`EG2C_INSTR_ADDR_W{1'b0}};
        dbg_instr_wdata = {`EG2C_INSTR_W{1'b0}};
        dbg_act0_we = 1'b0;
        dbg_act0_addr = {`EG2C_ACT_ADDR_W{1'b0}};
        dbg_act0_wdata = {`EG2C_DATA_W{1'b0}};
        dbg_act1_we = 1'b0;
        dbg_act1_addr = {`EG2C_ACT_ADDR_W{1'b0}};
        dbg_act1_wdata = {`EG2C_DATA_W{1'b0}};
        dbg_weight_we = 1'b0;
        dbg_weight_addr = {`EG2C_WEIGHT_ADDR_W{1'b0}};
        dbg_weight_wdata = {`EG2C_WEIGHT_W{1'b0}};
        dbg_index_we = 1'b0;
        dbg_index_addr = {`EG2C_INDEX_ADDR_W{1'b0}};
        dbg_index_wdata = {`EG2C_INDEX_W{1'b0}};

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        write_instr(10'd0, {`EG2C_OP_DONE, 24'h000000});
        write_act0(15'd3, 8'h2a);
        write_act1(15'd5, 8'h55);
        write_weight(15'd7, 8'hf6);
        write_index(13'd2, 16'h1234);

        check32("instr_mem[0]", dbg_instr_rdata, {`EG2C_OP_DONE, 24'h000000});
        check8("act_gb0[3]", dbg_act0_rdata, 8'h2a);
        check8("act_gb1[5]", dbg_act1_rdata, 8'h55);
        check8("weight_mem[7]", dbg_weight_rdata, 8'hf6);
        check16("index_mem[2]", dbg_index_rdata, 16'h1234);

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        cycles = 0;
        while (!done && cycles < 20) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        if (!done) begin
            $display("ERROR: top did not assert done within timeout");
            mismatches = mismatches + 1;
        end

        if (ctrl_opcode != `EG2C_OP_DONE) begin
            $display("ERROR: ctrl_opcode got=%02x expected=%02x", ctrl_opcode, `EG2C_OP_DONE);
            mismatches = mismatches + 1;
        end

        if (mismatches == 0) begin
            $display("target=smoke mismatches=0 PASS");
            $finish;
        end else begin
            $display("target=smoke mismatches=%0d FAIL", mismatches);
            $fatal(1);
        end
    end

    task write_instr;
        input [`EG2C_INSTR_ADDR_W-1:0] addr;
        input [`EG2C_INSTR_W-1:0] data;
        begin
            @(negedge clk);
            dbg_instr_addr = addr;
            dbg_instr_wdata = data;
            dbg_instr_we = 1'b1;
            @(negedge clk);
            dbg_instr_we = 1'b0;
        end
    endtask

    task write_act0;
        input [`EG2C_ACT_ADDR_W-1:0] addr;
        input [`EG2C_DATA_W-1:0] data;
        begin
            @(negedge clk);
            dbg_act0_addr = addr;
            dbg_act0_wdata = data;
            dbg_act0_we = 1'b1;
            @(negedge clk);
            dbg_act0_we = 1'b0;
        end
    endtask

    task write_act1;
        input [`EG2C_ACT_ADDR_W-1:0] addr;
        input [`EG2C_DATA_W-1:0] data;
        begin
            @(negedge clk);
            dbg_act1_addr = addr;
            dbg_act1_wdata = data;
            dbg_act1_we = 1'b1;
            @(negedge clk);
            dbg_act1_we = 1'b0;
        end
    endtask

    task write_weight;
        input [`EG2C_WEIGHT_ADDR_W-1:0] addr;
        input [`EG2C_WEIGHT_W-1:0] data;
        begin
            @(negedge clk);
            dbg_weight_addr = addr;
            dbg_weight_wdata = data;
            dbg_weight_we = 1'b1;
            @(negedge clk);
            dbg_weight_we = 1'b0;
        end
    endtask

    task write_index;
        input [`EG2C_INDEX_ADDR_W-1:0] addr;
        input [`EG2C_INDEX_W-1:0] data;
        begin
            @(negedge clk);
            dbg_index_addr = addr;
            dbg_index_wdata = data;
            dbg_index_we = 1'b1;
            @(negedge clk);
            dbg_index_we = 1'b0;
        end
    endtask

    task check8;
        input [127:0] name;
        input [7:0] got;
        input [7:0] expected;
        begin
            #1;
            if (got !== expected) begin
                $display("ERROR: %0s got=%02x expected=%02x", name, got, expected);
                mismatches = mismatches + 1;
            end
        end
    endtask

    task check16;
        input [127:0] name;
        input [15:0] got;
        input [15:0] expected;
        begin
            #1;
            if (got !== expected) begin
                $display("ERROR: %0s got=%04x expected=%04x", name, got, expected);
                mismatches = mismatches + 1;
            end
        end
    endtask

    task check32;
        input [127:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            #1;
            if (got !== expected) begin
                $display("ERROR: %0s got=%08x expected=%08x", name, got, expected);
                mismatches = mismatches + 1;
            end
        end
    endtask

endmodule

`default_nettype wire
