# e-G2C Beginner Explanation

Audience:
- You have written small FPGA blocks such as SPI, UART, counters, FIFOs, or simple FSMs.
- You have not built a neural-network accelerator before.

This document explains what this repository implements, how the hardware blocks fit together, and how the simulation flow proves that the RTL behaves as intended.

Read this file first for the mental model. Then use:
- `e-G2C/PROJECT_GUIDE.md` for the module and command map;
- `e-G2C/IMPLEMENTATION_PLAN.md` for generated artifact contracts, milestone scope, assumptions, and acceptance criteria;
- `e-G2C/PAPER_NOTES.md` for paper facts and implementation assumptions.

## 1. The Short Version

e-G2C is a neural-network processor architecture for a pacemaker monitoring workload.

In this project, EGM is the pacemaker-sensed input signal, and ECG is the reconstructed or converted output signal.

The paper-level idea is:

```text
EGM heartbeat signal
        |
        v
small detector decides normal or abnormal
        |
        +-- normal   -> cheaper coarse EGM-to-ECG converter
        |
        +-- abnormal -> more expensive precise EGM-to-ECG converter

over time: detector scores update the threshold used by the detector branch
```

Current RTL note: the integrated top does not implement the detector CNN itself. It receives a detector score as `score_i`, compares that score with `threshold_i`, and then chooses the coarse or precise converter path.

This repository does not reproduce the full medical model, real trained weights, ASIC layout, area, or power. It builds a deterministic, simulation-friendly Verilog model that exercises the same kinds of architectural blocks:
- memories;
- multiply-accumulate arithmetic;
- dense convolution and pooling;
- sparse-vector skipping;
- depth-wise reuse schedules;
- detector threshold branching;
- threshold adaptation;
- an integrated toy top-level regression.

The current full regression command is:

```bash
./sim/run_sim.sh all
```

The current integrated toy system is:

```bash
./sim/run_sim.sh top
```

## 2. From SPI Thinking To Accelerator Thinking

If you have written an SPI controller, you already know several ideas that transfer directly.

| SPI/FSM idea | Accelerator equivalent |
|---|---|
| A command byte tells the SPI block what to do | An instruction opcode tells the pipeline which layer to run |
| Shift registers hold bytes while a transaction runs | Activation and weight vectors hold data while a layer runs |
| A clocked FSM sequences states such as IDLE, TRANSFER, DONE | Convolution/pooling FSMs sequence nested loops over pixels, channels, and kernel taps |
| A FIFO or RAM decouples producer and consumer timing | Activation, weight, index, and instruction memories hold tensors and metadata |
| A checksum accumulates bytes | A MAC accumulates activation * weight products |
| `start`, `busy`, and `done` define a transaction boundary | Every compute module uses a transaction-like start/busy/done protocol |

The main difference is data volume and loop structure. A SPI block sends bytes in a simple order. A convolution engine repeatedly reuses the same activations and weights across many output positions. The accelerator is mostly a collection of FSMs and memories arranged so those repeated multiply-accumulate operations are efficient.

## 3. Minimum Neural-Network Vocabulary

You do not need a machine-learning background to read this RTL. You do need a few data names.

| Term | Hardware meaning in this project |
|---|---|
| Activation | A data value flowing between layers. It is like a sample stored in activation RAM. |
| Weight | A learned coefficient multiplied by an activation. In this model it is signed 8-bit data. |
| Channel | One parallel signal stream at each pixel/time position. For example, an input can have `IN_C=2` channels. |
| Kernel | A small window of weights, such as `3x3`, used by convolution. |
| Feature map | A 2D grid of activations with one or more channels. |
| Tensor | A multi-dimensional array. In this repo, tensors are flattened into Verilog vectors or hex files. |
| MAC | Multiply-accumulate: `acc = acc + activation * weight`. |

Current numeric rules:
- activations: signed 8-bit two's-complement;
- weights: signed 8-bit two's-complement;
- accumulators: signed 32-bit;
- layer output activations in the current models: signed 8-bit with saturation to `[-128, 127]`;
- addresses: word addresses, not byte addresses.

The common activation layout is `NHWC` without the batch dimension in the toy tests:

```text
flat_index = (y * width + x) * channels + channel
```

For normal convolution weights, the common layout is:

```text
flat_index = (((kernel_y * kernel_w + kernel_x) * input_channels + input_channel) * output_channels) + output_channel
```

In a hex file, `ff` means the 8-bit bit pattern `11111111`. When interpreted as signed int8, that is `-1`, not `255`.

## 4. What A Convolution Does In Hardware

A normal 2D convolution is a sliding-window multiply-accumulate.

For each output pixel and output channel:

```text
acc = 0
for each kernel row:
  for each kernel column:
    for each input channel:
      acc += input_activation * weight
output = saturate_to_int8(acc)
```

In this repository, `rtl/eg2c_dense_conv2d.v` models that as an FSM that advances through those loop indices. The model is intentionally small and simple: it performs one multiply-accumulate term per simulated cycle. That is good for verifying address order and arithmetic, but it is not a fully parallel ASIC datapath.

Other layer types:

| Layer | Plain meaning | RTL target |
|---|---|---|
| Normal convolution | A 3x3 sliding filter that mixes input channels into output channels | `eg2c_dense_conv2d.v` |
| Depth-wise convolution | A 3x3 sliding filter applied independently per channel | `eg2c_dw_conv2d.v` |
| Point-wise convolution | A 1x1 convolution that mixes channels at each pixel | `eg2c_pw_conv2d.v` |
| Average pooling | Average a small window to downsample | `eg2c_avg_pool2d.v` |

## 5. The Important Top-Level Distinction

There are two files with "top-like" names:

| File | What it is | What it is not |
|---|---|---|
| `rtl/eg2c_top.v` | A smoke-test shell with memories, debug ports, controller, buffers, and MAC array instantiated | Not the current integrated accelerator behavior |
| `rtl/eg2c_integrated_top.v` | The current architecture-level integrated toy system | Not a cycle-accurate ASIC or the full trained e-G2C model |

When you want to understand the current integrated behavior, start with:

```text
rtl/eg2c_integrated_top.v
tb/tb_top.v
scripts/golden_eg2c.py   # gen_top()
```

`eg2c_top.v` is still useful because it shows the paper-shaped shell: instruction SRAM, activation memories, weight memory, index memory, buffers, MAC array, and controller. But its MAC array is not connected to a real layer scheduler in the smoke target.

## 6. Current Integrated Dataflow

The integrated toy top takes these important inputs:
- `score_i`: detector score for the current window;
- `threshold_i`: threshold used for the current branch decision;
- `input_act_i`: toy activation tensor;
- `coarse_weight_i`: weights for the coarse converter;
- `precise_weight_i`: weights for the precise converter;
- optional adaptation score window inputs.

The simplified flow is:

```text
                         +----------------------+
score_i, threshold_i --->| detector branch      |
                         | score >= threshold ? |
                         +----------+-----------+
                                    |
                  false/coarse -----+----- true/precise
                       |                          |
                       v                          v
             +----------------+          +-----------------+
             | coarse dense   |          | precise dense   |
             | pipeline       |          | pipeline        |
             +-------+--------+          +--------+--------+
                     |                            |
                     +-------------+--------------+
                                   |
                                   v
                             selected_act_o

Optional in parallel:

adapt_scores_i -> histogram -> argmin quiet interval -> updated threshold_o
```

Important behavior:
- Only the selected converter path is started.
- The branch decision for the current transaction uses the input `threshold_i`.
- The adaptation engine updates `threshold_o` for future windows; it does not change the current branch decision.
- `start_i` is accepted only on a rising edge while the top is idle.
- Adaptation control and score inputs are latched at transaction start, so changing them mid-run does not change the current transaction.
- If the selected converter reports an error, `selected_act_o` is forced to zero.

The `top` regression covers five cases:
- normal score, coarse path;
- abnormal score, precise path, with adaptation;
- precise path illegal opcode after a previous precise transaction without reset;
- coarse path illegal opcode;
- invalid adaptation length rejected before converter launch.

Run it with:

```bash
./sim/run_sim.sh top
```

## 7. Dense Pipeline

`rtl/eg2c_dense_pipeline.v` is an instruction-driven toy pipeline.

It has a small instruction memory input and supports a compact set of opcodes:
- `CONV`;
- `POOL`;
- `NOP`;
- `DONE`;
- unsupported opcodes produce `error_o`.

For legal work, the intended order is:

```text
CONV -> POOL -> DONE
```

The dense pipeline starts `eg2c_dense_conv2d`, waits for `conv_done`, then allows pooling. It rejects `POOL` before a current-transaction `CONV`, because that would otherwise consume stale convolution output.

Run the pipeline regression with:

```bash
./sim/run_sim.sh pipeline_dense
```

That target checks five generated programs:
- `CONV -> POOL -> DONE`;
- `DONE` only;
- `NOP -> CONV -> POOL -> DONE`;
- illegal opcode;
- `POOL -> DONE` dependency error.

## 8. Memories And Buffers

The paper describes separate SRAM-like memories. This repository models them behaviorally:

| RTL file | Purpose |
|---|---|
| `rtl/eg2c_act_mem.v` | Activation memory |
| `rtl/eg2c_weight_mem.v` | Weight memory |
| `rtl/eg2c_index_mem.v` | Sparse index memory |
| `rtl/eg2c_instr_mem.v` | Instruction memory |

These are Verilog `reg` arrays with simple read/write behavior. They are not ASIC SRAM macros.

The buffer modules are currently simple:
- `rtl/eg2c_input_act_buffer.v` is a pass-through selection shell;
- `rtl/eg2c_output_act_buffer.v` is a small output-register style buffer.

They exist so the project shape matches the paper architecture and can be refined later.

## 9. MAC Lanes And MAC Array

`rtl/eg2c_mac_lane.v` is the smallest arithmetic block:

```text
if clear:
  accumulator = 0
else if valid:
  accumulator += activation * weight
```

`rtl/eg2c_mac_array.v` uses Verilog `generate` to instantiate 32 lanes. If you have used a generate loop to create repeated SPI chip-select logic or repeated counters, this is the same idea.

One important limitation: the current convolution modules do not drive the 32-lane MAC array as their main datapath. The convolution modules are behavior-level schedulers with their own multiply-accumulate loop. So do not read the current model as a finished parallel MAC-array implementation.

## 10. Sparse Support

Sparse means many weight groups are zero, so the hardware can skip some work.

Current sparse pieces:

| Target | What it verifies |
|---|---|
| `sparse` | A standalone sparse vector MAC skips invalid vectors and still matches dense output |
| `conv_sparse` | Normal convolution skips all-zero sparse weight vectors while matching dense output |
| `pw_sparse` | Point-wise convolution skips all-zero sparse weight vectors while matching dense output |

The core idea is:

```text
if vector_valid:
  process this sparse vector
else:
  count one skipped vector and move on
```

Current limitation:
- `eg2c_integrated_top.v` runs dense converter paths.
- Its `sparse_skipped_count_o` is expected to be zero.
- Full compressed weight/index streaming into the integrated top remains future work.

## 11. Depth-Wise Reuse

Depth-wise convolution is different from normal convolution because each channel is processed independently. The paper proposes reuse patterns called CIR and D-RIR.

CIR means column-wise intra-channel reuse. D-RIR means deeper row-wise intra-channel reuse. In this project, both are lane/schedule optimization models; they do not change the mathematical convolution result.

This repository verifies a standalone schedule model in:

```text
rtl/eg2c_dw_reuse_conv2d.v
tb/tb_dw_reuse.v
```

It compares three schedules:
- simple;
- CIR;
- D-RIR.

The target checks that all three produce the same output tensor and match generated schedule traces/counters. This is an architecture-level scheduling model, not a claim that every cycle matches the ASIC implementation in the paper.

Run it with:

```bash
./sim/run_sim.sh dw_reuse
```

## 12. Threshold Adaptation

The detector threshold should not be fixed forever. The adaptation engine watches a window of detector scores and finds a quiet interval in the score histogram.

Flow:

```text
score stream
    |
    v
classify each score into an interval
    |
    v
histogram counters
    |
    v
choose interval with minimum count
    |
    v
threshold = midpoint of that interval
```

Implemented in:

```text
rtl/eg2c_adapt_engine.v
tb/tb_adapt.v
```

Important rules:
- interval lower bound is inclusive;
- interval upper bound is exclusive, except the final interval includes its upper bound;
- out-of-range scores are ignored by the histogram;
- ties choose the lowest interval index;
- histogram counters saturate rather than wrap;
- if update and score-valid happen together, the score is counted before argmin.

Run it with:

```bash
./sim/run_sim.sh adapt
```

## 13. What Is Architecture-Level Here

This project intentionally does not claim bit-accurate or cycle-accurate ASIC reproduction.

Architecture-level means:
- the dataflow shape matches the paper's blocks;
- arithmetic and tensor indexing are deterministic and checked;
- sparse skipping and schedule counters are modeled;
- control protocols are simulated with `start`, `busy`, `done`, and `error`;
- tests use small toy tensors so regressions run quickly.

It does not mean:
- real e-G2C trained weights are present;
- clinical ECG accuracy is reproduced;
- ASIC SRAM macros are modeled;
- 28 nm timing, power, or area are reproduced;
- every cycle matches the published chip.

## 14. How A Simulation Target Works

Most targets use the same flow:

```text
./sim/run_sim.sh <target>
  |
  v
choose tb/tb_<target>.v
  |
  v
create sim/build/<target>/
  |
  v
scripts/golden_eg2c.py writes input files and expected files
  |
  v
scripts/validate_manifest.py checks generated file integrity
  |
  v
iverilog compiles RTL + testbench
  |
  v
vvp runs simulation
  |
  v
testbench reads hex/bin files, drives DUT, compares results
```

Example:

```bash
./sim/run_sim.sh conv
```

Typical pass output:

```text
manifest OK: .../sim/build/conv
target=conv mismatches=0 PASS cycles=864
```

`manifest OK` only means the generated files are present and match their hashes. It does not mean RTL passed. The actual pass condition is the target line with `mismatches=0 PASS`.

## 15. Golden Data

`scripts/golden_eg2c.py` is the Python reference model. It writes files such as:

| File | Meaning |
|---|---|
| `input_act.hex` | Input activation values |
| `weights.hex` | Weight values |
| `expected.hex` | Expected output activations |
| `expected_status.hex` | Expected status fields such as error/op count/cycles |
| `expected_stats.hex` | Expected counters for sparse/adaptation/schedule targets |
| `expected_histogram.hex` | Expected adaptation histogram counters |
| `target.json` | Human-readable target specification |
| `manifest.json` | File integrity record |

The Verilog testbenches normally do not use `target.json` to drive behavior. They read the hex/bin files and compare DUT outputs against those expected values.

`smoke` and `mac` are simpler hand-written tests and do not rely on the Python generator in the same way.

## 16. Waveforms

Some targets support VCD output:

```bash
./sim/run_sim.sh top wave
```

That creates:

```text
sim/build/top/wave.vcd
```

Use GTKWave from a graphical environment to inspect it. The `wave` option is for debugging; it does not change the PASS/FAIL rules.

The `all` target does not support wave output because it runs many targets.

## 17. Recommended Reading Order

For a new reader:

1. Read this file.
2. Read `e-G2C/PROJECT_GUIDE.md` for the module list and command list.
3. Run `./sim/run_sim.sh top`.
4. Open `rtl/eg2c_integrated_top.v`.
5. Open `tb/tb_top.v`.
6. Search `gen_top` in `scripts/golden_eg2c.py`.
7. Run `./sim/run_sim.sh all`.
8. Read `e-G2C/PAPER_NOTES.md` for paper facts and assumptions.
9. Read `e-G2C/BUGFIX.md` to understand the protocol bugs already fixed.

Use `guide_ref/` only as historical reference from a different project. It is not the entry point for this e-G2C implementation.

## 18. Common Misreadings

Avoid these mistakes:

- Do not treat `eg2c_top.v` as the complete integrated accelerator. Use `eg2c_integrated_top.v` for that.
- Do not assume the detector CNN is implemented inside `eg2c_integrated_top.v`; the top receives `score_i`.
- Do not assume adaptation changes the current branch decision; it updates `threshold_o` for future windows.
- Do not assume sparse streaming is fully wired into the integrated top; sparse behavior is verified by standalone targets.
- Do not assume the 32-lane MAC array drives the current convolution modules; the current convolution models use sequential multiply-accumulate loops.
- Do not compare this simulation's cycle counters to the paper's ASIC performance numbers.
- Do not read hex values as unsigned unless the target says so; most activation/weight values are signed two's-complement.

## 19. Where To Change Things

If you want to add a new operation or target, the usual places are:

| Goal | Files to touch |
|---|---|
| Add a new RTL block | `rtl/`, then a matching `tb/tb_*.v` |
| Add generated test data | `scripts/golden_eg2c.py` |
| Add a simulation command | `sim/run_sim.sh` |
| Document generated files | `scripts/README.md` and `e-G2C/IMPLEMENTATION_PLAN.md` |
| Record project status | `e-G2C/TODO.md` and `e-G2C/LOG.md` |
| Record a bug and prevention rule | `e-G2C/BUGFIX.md` |

Keep the pattern small:

```text
one RTL behavior -> one Python golden -> one testbench -> one run_sim target
```

That is the same discipline you would use for a SPI controller: first prove one transaction, then add features only after the smaller case is checked.
