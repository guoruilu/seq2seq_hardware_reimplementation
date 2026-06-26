`ifndef EG2C_DEFINES_VH
`define EG2C_DEFINES_VH

// Widths used by the first architecture-level simulation baseline.
`define EG2C_DATA_W         8
`define EG2C_WEIGHT_W       8
`define EG2C_INDEX_W        16
`define EG2C_ACC_W          32
`define EG2C_INSTR_W        32
`define EG2C_LANE_COUNT     32

// Paper-derived memory capacities, modeled as word-addressed simulation SRAMs.
`define EG2C_ACT_DEPTH      25600
`define EG2C_ACT_ADDR_W     15
`define EG2C_WEIGHT_DEPTH   32768
`define EG2C_WEIGHT_ADDR_W  15
`define EG2C_INDEX_DEPTH    5120
`define EG2C_INDEX_ADDR_W   13
`define EG2C_INSTR_DEPTH    1024
`define EG2C_INSTR_ADDR_W   10

// Minimal simulation opcodes. The complete instruction format is defined later.
`define EG2C_OP_NOP         8'h00
`define EG2C_OP_DONE        8'hff

// Controller states exposed for smoke/debug tests.
`define EG2C_CTRL_IDLE      3'd0
`define EG2C_CTRL_FETCH     3'd1
`define EG2C_CTRL_DECODE    3'd2
`define EG2C_CTRL_RUN       3'd3
`define EG2C_CTRL_DONE      3'd4

`endif
