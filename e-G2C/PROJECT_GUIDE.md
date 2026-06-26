# e-G2C Verilog Project Guide

> Audience: a Verilog beginner who has written simple FSMs, UART, or SPI, but has not built a neural-network accelerator.

## 1. What We Are Building

We are building a simulation-friendly Verilog model of the e-G2C processor.

The processor has two jobs:
1. Detect whether an EGM heartbeat is normal or abnormal.
2. Convert EGM signals into ECG signals using either a cheap coarse converter or a more expensive precise converter.

The first implementation target is not a medical-quality model. It is a hardware architecture reproduction that can run deterministic toy data through the same kinds of engines described in the paper.

## 1.1 Path Convention

Code directories are currently at the repository root:

| Path | What goes there |
|---|---|
| `rtl/` | Verilog RTL |
| `tb/` | Verilog testbenches |
| `sim/` | Simulation runner and generated simulation outputs |
| `scripts/` | Python generators and golden references |
| `e-G2C/` | Paper PDF, e-G2C-specific documents, and extracted paper assets |

So `rtl/eg2c_top.v` means `/mnt/e/prjs/Vib2ECG_hardware/reimplementation/rtl/eg2c_top.v`, not `e-G2C/rtl/eg2c_top.v`.

## 2. Kitchen Analogy

Think of e-G2C as a shared kitchen:

| Kitchen idea | e-G2C hardware |
|---|---|
| Recipe cards | 32-bit instructions in Instruction SRAM |
| Pantry | Weight global buffer |
| Shelf labels | Index SRAM for sparse weights |
| Two prep tables | Activation GB0 and GB1 |
| Cutting board | Input activation buffer |
| 32 cooks | 32 MAC lanes |
| Serving tray | Output activation buffer |
| Kitchen manager | Controller |
| Quality checker | Detector threshold comparator |
| Daily taste adjustment | Threshold adaptation engine |

The kitchen does not build three separate machines for detector/coarse/precise models. It reuses the same cooks and tables, then changes the recipe.

## 3. Top-Level Dataflow

```text
                   +----------------+
                   | Instruction    |
                   | SRAM           |
                   +--------+-------+
                            |
                            v
EGM input ---> Act GB input role ---> Input Act Buffer ---> MAC Lane Array
                    ^                                          |
                    |                                          v
              Act GB output role <--- Output Act Buffer <--- Accumulate/Clamp

Detector output ---> Threshold Compare ---> choose coarse or precise converter
                                  |
                                  v
                         Adaptation Engine
```

The two activation memories swap roles layer by layer. One holds the current layer input while the other receives the output.

## 4. Module List

Planned RTL files:

| File | Responsibility |
|---|---|
| `rtl/eg2c_defines.vh` | Shared constants, opcodes, widths, memory sizes |
| `rtl/eg2c_act_mem.v` | Behavioral activation global buffer |
| `rtl/eg2c_weight_mem.v` | Behavioral weight global buffer |
| `rtl/eg2c_index_mem.v` | Behavioral index SRAM |
| `rtl/eg2c_instr_mem.v` | Behavioral instruction SRAM |
| `rtl/eg2c_mac_lane.v` | One lane that multiplies activation values by weights and accumulates |
| `rtl/eg2c_mac_array.v` | 32-lane array |
| `rtl/eg2c_input_act_buffer.v` | Holds selected activation rows/elements for MAC lanes |
| `rtl/eg2c_output_act_buffer.v` | Collects and writes output activations |
| `rtl/eg2c_dense_conv2d.v` | Normal convolution schedule with dense mode and optional sparse weight-vector skipping |
| `rtl/eg2c_dw_conv2d.v` | Baseline depth-wise convolution schedule |
| `rtl/eg2c_dw_reuse_conv2d.v` | DW simple/CIR/D-RIR lane-assignment scheduler with cycle and lane-utilization counters |
| `rtl/eg2c_pw_conv2d.v` | Point-wise convolution schedule with dense mode and optional sparse weight-vector skipping |
| `rtl/eg2c_detector_branch.v` | Signed detector threshold comparison and coarse/precise path selection |
| `rtl/eg2c_sparse_selector.v` | Vector-wise sparse activation selection |
| `rtl/eg2c_sparse_vector_mac.v` | Architecture-level sparse vector MAC with active/skip counters |
| `rtl/eg2c_adapt_engine.v` | Threshold adaptation histogram, lower-index argmin tie-break, threshold midpoint update, and counter reset |
| `rtl/eg2c_controller.v` | Current smoke/top-shell instruction walker with invalid-opcode and instruction-bound error reporting; operation-specific dense scheduling is in `eg2c_dense_pipeline.v` |
| `rtl/eg2c_top.v` | Current memory/controller smoke shell; full integrated toy top remains future work |

The first milestone may combine some modules if that keeps the code easier to verify. If modules are split later, the guide must be updated.

Phase 1 still creates `eg2c_input_act_buffer.v` and `eg2c_output_act_buffer.v`, even if they start as pass-through shells. This keeps the top-level shape aligned with the paper's Fig. 2 from the beginning.

## 5. Instruction Model

The paper says the controller reads 32-bit instructions, but it does not publish the full encoding.

For this project we will define a practical simulation encoding:

| Field | Purpose |
|---|---|
| opcode | layer type: conv, depth-wise conv, point-wise conv, pooling, threshold, done |
| sparse_en | dense mode or vector-sparse mode |
| in_base | activation input base address |
| out_base | activation output base address |
| weight_base | weight memory base address |
| index_base | index memory base address |
| shape_id or context index | selects dimensions from a small context table |

If 32 bits becomes too tight for clear simulation, the implementation may use a 32-bit instruction plus a separate context memory. That keeps the paper-facing instruction SRAM while avoiding unreadable bit packing.

## 6. Verification Strategy

Each stage gets a small test before integration:

| Stage | Test |
|---|---|
| MAC lane | multiply-accumulate against hand-computed values |
| MAC array | lane packing and output ordering |
| Act/weight/index memories | read/write smoke tests |
| Dense Conv | Python golden for tiny tensor |
| DW Conv | Python golden for tiny tensor |
| DW reuse lane schedules | Python golden output plus per-cycle simple/CIR/D-RIR trace checks |
| PW Conv | Python golden for tiny tensor |
| Sparse Normal Conv | Python golden for dense-equivalent output plus active/skip counters |
| Sparse PW Conv | Python golden for dense-equivalent output plus active/skip counters |
| Sparse selector | compressed vector result equals dense result |
| Adaptation engine | histogram, ignored out-of-range samples, argmin, threshold update, and restart behavior match Python golden |
| Top pipeline | toy detector chooses coarse/precise path correctly |

The pass condition is always printed by the testbench as a mismatch count.

The milestone order is:

| Milestone | Command |
|---|---|
| Skeleton | `./sim/run_sim.sh smoke` |
| MAC arithmetic | `./sim/run_sim.sh mac` |
| Dense normal conv | `./sim/run_sim.sh conv` |
| Dense depth-wise conv | `./sim/run_sim.sh dw` |
| Dense point-wise conv | `./sim/run_sim.sh pw` |
| Average pooling | `./sim/run_sim.sh pool` |
| Dense instruction pipeline | `./sim/run_sim.sh pipeline_dense` |
| Detector branch | `./sim/run_sim.sh branch` |
| Sparse vector MAC | `./sim/run_sim.sh sparse` |
| Sparse normal conv | `./sim/run_sim.sh conv_sparse` |
| Sparse point-wise conv | `./sim/run_sim.sh pw_sparse` |
| DW reuse lane schedules | `./sim/run_sim.sh dw_reuse` |
| Threshold adaptation | `./sim/run_sim.sh adapt` |
| Full implemented regression | `./sim/run_sim.sh all` |
| Integrated toy system | planned: `./sim/run_sim.sh top` |

Generated test data goes under `sim/build/<target>/`. Hex file formats and PASS/FAIL rules are defined in `IMPLEMENTATION_PLAN.md`.

## 7. Expected Limitations

The first architecture-level version will use:
- deterministic toy inputs;
- deterministic pseudo-random weights;
- simple signed integer arithmetic;
- fixed shapes small enough for fast simulation.

It will not use:
- real patient data;
- real trained weights;
- real ASIC SRAM macros;
- power estimation;
- 28 nm timing closure.

Those can be future stages after the architecture is stable.
