# e-G2C Detailed Implementation Plan

> Current target: architecture-level Verilog reproduction that runs in Icarus Verilog.
>
> Current non-target: reproducing clinical accuracy, ASIC power, area, or measured energy.

## Path Convention

All code paths in this plan are relative to the repository root:

| Path | Purpose |
|---|---|
| `rtl/` | Verilog RTL shared by the e-G2C reproduction |
| `tb/` | Verilog testbenches |
| `sim/` | Simulation runner and generated simulator outputs |
| `scripts/` | Python generators, golden references, and extraction helpers |
| `build/` | Disposable build products if a script needs a root-level build directory |
| `e-G2C/` | Paper PDF, paper-specific documents, and extracted paper assets |
| `e-G2C/extracted/` | Text, page images, and cropped figures extracted from the paper |

If this repository later hosts more than one implementation, the RTL/script directories may be moved under a paper-specific subdirectory. Until then, use the root-level code directories above and keep all e-G2C documents under `e-G2C/`.

## Generated Artifact Contract

All simulation-generated files should be deterministic and disposable.

Default output directory:
- `sim/build/<target>/`

Standard files:

| File | Producer | Consumer | Format |
|---|---|---|---|
| `input_act.hex` | Python generator | testbench activation memory loader | one 8-bit two's-complement value per line, hex without `0x` |
| `weights.hex` | Python generator | testbench weight memory loader | one signed weight per line; 8-bit int mode uses 2 hex digits, while 4-bit packed/power-of-2 weight mode remains future weight-format work |
| `indices.hex` | Python generator | testbench index memory loader | one unsigned index word per line; width documented per target |
| `instr.hex` | Python generator | instruction SRAM loader | one 32-bit instruction per line, big-endian human-readable hex |
| `ctx.hex` | Python generator | optional context memory loader | one context word per line; width documented in the target README/header |
| `scores.hex` / `thresholds.hex` | Python generator | branch testbench | signed 8-bit detector score and threshold values |
| `scores.hex` / `boundaries.hex` / `initial_thresholds.hex` | Python generator | adaptation testbench | signed 8-bit detector scores, interval boundaries, and per-window initial thresholds |
| `case_lengths.hex` | Python generator | adaptation testbench | one 32-bit score-window length per adaptation case |
| `coarse.hex` / `precise.hex` | Python generator | branch testbench | one signed 8-bit output vector entry per line for coarse and precise candidate paths |
| `expected_path.bin` | Python generator | branch testbench | one binary path bit per branch case; `1` means precise/abnormal |
| `vector_valid.bin` | Python generator | sparse schedule testbenches | one binary validity bit per sparse vector |
| `expected_status.hex` | Python generator | `pipeline_dense` testbench | repeated per case: `expected_error`, `expected_ops`, `expected_cycles` |
| `expected_histogram.hex` | Python generator | adaptation testbench | repeated per adaptation case: one 32-bit expected counter value per interval |
| `expected_stats.hex` | Python generator | sparse, adaptation, and schedule-counter testbenches | sparse MAC order: `dense_accumulator`, `active_sparse_cycles`, `skipped_vectors`, `dense_equivalent_cycles`, `total_sparse_cycles`; sparse conv/PW order: `dense_equivalent_cycles`, `active_sparse_cycles`, `skipped_vectors`, `total_sparse_cycles`; DW reuse order: `simple_cycles`, `cir_cycles`, `drir_cycles`, `simple_active_slots`, `cir_active_slots`, `drir_active_slots`, `simple_idle_slots`, `cir_idle_slots`, `drir_idle_slots`; adaptation order per case: `updated_threshold`, `selected_interval`, `accepted_samples`, `ignored_samples`, `total_samples` |
| `target.json` | Python generator | Python golden, RTL testbench documentation | target shape/layout/padding/stride/arithmetic assumptions |
| `adapt_target.json` | Python generator | adaptation golden and testbench documentation | threshold interval boundaries, score format, counter width, update window |
| `expected.hex` | Python golden | testbench checker | one signed output activation per line for activation-producing targets; first baseline uses 8-bit two's-complement hex; branch target stores the vector selected by `expected_path.bin`; `adapt` is golden-checked through `expected_histogram.hex` and `expected_stats.hex` instead |
| `manifest.json` | Python generator | simulation runner | generated artifact line counts, byte counts, and sha256 hashes checked before `iverilog` |
| `sim.vvp` | `iverilog` | `vvp` | compiled simulation |
| `wave.vcd` | testbench when `wave` is passed | GTKWave | optional waveform |

Numeric rules for the first dense baseline:
- Activation: signed 8-bit two's complement.
- Weight: signed 8-bit two's complement.
- Accumulator: signed 32-bit.
- Output: signed 8-bit, saturated to `[-128, 127]`.
- Address unit: one activation, weight, index, or instruction word, not byte address.
- Tensor layout: NHWC-flattened for activations (`h, w, c` contiguous in `c`), and `kh, kw, cin, cout` for normal convolution weights unless a target explicitly overrides it.

Testbench PASS/FAIL contract:
- Every test prints a target name.
- Every checker prints `mismatches=<N>`.
- A passing test prints `PASS`.
- Any mismatch or timeout prints `FAIL` and exits with a non-zero simulation status when possible.

## Milestone Ladder

Milestones are intentionally small. Do not skip ahead to a full pipeline before the lower level checks pass.

| Milestone | Command | Meaning |
|---|---|---|
| M0 | `./sim/run_sim.sh smoke` | RTL skeleton compiles, memories load, top-level start/done works |
| M1 | `./sim/run_sim.sh mac` | MAC lane and MAC array arithmetic match hand/Python golden |
| M2A | `./sim/run_sim.sh conv` | one dense normal convolution target passes |
| M2B | `./sim/run_sim.sh dw` | one dense depth-wise convolution target passes |
| M2C | `./sim/run_sim.sh pw` | one dense point-wise convolution target passes |
| M2D | `./sim/run_sim.sh pool` | one average-pooling target passes |
| M3 | `./sim/run_sim.sh pipeline_dense` | instruction-driven dense CONV -> POOL -> DONE toy pipeline passes |
| M4 | `./sim/run_sim.sh branch` | detector threshold selects coarse and precise paths correctly |
| M5 | `./sim/run_sim.sh sparse` | vector-wise sparse MAC model matches dense dot-product output and reports skipped work |
| M5A | `./sim/run_sim.sh conv_sparse` | normal convolution schedule skips all-zero sparse weight vectors while matching dense output |
| M5B | `./sim/run_sim.sh pw_sparse` | point-wise convolution schedule skips all-zero sparse weight vectors while matching dense output |
| M6 | `./sim/run_sim.sh dw_reuse` | DW simple/CIR/D-RIR lane-assignment schedules match the same golden output and print utilization counters |
| M7 | `./sim/run_sim.sh adapt` | threshold adaptation engine matches Python golden |
| M8 | `./sim/run_sim.sh top` | integrated e-G2C toy system passes normal and abnormal scenarios |

`./sim/run_sim.sh all` runs every currently implemented target through M8.

## Phase 0 -- Setup And Paper Extraction

Goal:
- Make the paper easy to inspect while implementing.
- Establish documentation and simulation conventions.

Tasks:
- Verify tools: `iverilog`, `vvp`, `pdftotext`, `pdfimages`, `gtkwave`.
- Extract text from `e-G2C/2022_VLSI_e-G2C.pdf` to `e-G2C/extracted/paper_text.txt`.
- Extract page images to `e-G2C/extracted/pages/page_01.png` and `page_02.png`.
- Extract or crop key figures to `e-G2C/extracted/figures/fig_01_pipeline.png`, `fig_02_arch.png`, and so on.
- Add `e-G2C/extracted/README.md` listing every extracted file and the command or script that created it.
- Keep `PAPER_NOTES.md` updated with facts and assumptions.
- Record missing details in `PAPER_NOTES.md` before choosing implementation assumptions.
- If external sources are used, record source title, URL, access date, and whether it is primary or secondary evidence.

Deliverables:
- Extracted text and images.
- Extracted asset README.
- Initial project documents.

Acceptance:
- A new contributor can read `PAPER_NOTES.md` and understand what facts came from the paper.
- Every paper-derived implementation choice has either a paper citation or an explicit assumption entry.

## Phase 1 -- Minimal RTL Skeleton

Goal:
- Build a compileable top-level processor shell with memories, controller, and MAC array interfaces.

Planned files:
- `rtl/eg2c_defines.vh`
- `rtl/eg2c_act_mem.v`
- `rtl/eg2c_weight_mem.v`
- `rtl/eg2c_index_mem.v`
- `rtl/eg2c_instr_mem.v`
- `rtl/eg2c_input_act_buffer.v`
- `rtl/eg2c_output_act_buffer.v`
- `rtl/eg2c_mac_lane.v`
- `rtl/eg2c_mac_array.v`
- `rtl/eg2c_controller.v`
- `rtl/eg2c_top.v`

Design choices:
- Use behavioral memories with async read or simple registered read, chosen per module and documented.
- Use signed integer arithmetic.
- Parameterize lane count, data width, weight width, and accumulator width.
- Provide testbench backdoor writes for fast simulation.
- In Phase 1, input/output activation buffers may be pass-through shells. They must still exist as modules so the top-level architecture matches Fig. 2 and later phases can replace pass-through behavior with real buffering.

Verification:
- Compile all RTL with `iverilog -Wall -g2012`.
- Run a smoke test that writes memories, starts the top, and observes `done`.

Acceptance:
- `./sim/run_sim.sh smoke` compiles and prints PASS.

## Phase 2 -- MAC Lane And Dense Arithmetic

Goal:
- Make arithmetic behavior correct before optimizing dataflow.

Tasks:
- Implement one MAC lane:
  - load activation vector;
  - load weight vector;
  - multiply element-wise;
  - accumulate into a wider signed accumulator;
  - clamp or truncate to output width.
- Implement 32-lane packing in `eg2c_mac_array.v`.
- Add cycle counters for later speedup comparison.

Verification:
- `tb/tb_mac.v`: hand-computed MAC lane vectors plus multiple-lane MAC array ordering.

Acceptance:
- MAC tests report `0` mismatches.

## Phase 3 -- Dense Operation Baseline

Goal:
- Implement behaviorally correct dense convolution modes before sparse support.

Supported operations:
- Normal 2D convolution.
- Depth-wise 2D convolution.
- Point-wise 1x1 convolution.
- Average pooling for detector.

Plain-language reason:
- Dense mode is the "full recipe." Sparse mode is a shortcut that skips empty ingredients. We first need the full recipe to prove the answer is right.

Shared assumptions to freeze before coding Phase 3:
- Padding: start with explicit zero padding controlled by context fields; default tests use `same` padding for `3x3` conv.
- Stride: default `1` for convolution and point-wise convolution; pooling target uses stride equal to pool size unless stated otherwise.
- Activation function: default linear output with optional ReLU disabled in first tests; saturation to signed 8-bit always happens at memory write.
- Quantization: no scale/zero-point in the first dense baseline; accumulator saturates directly to signed 8-bit output.
- Layout: NHWC activations and `kh, kw, cin, cout` normal-conv weights.
- Golden alignment: Python and RTL must share one generated target descriptor saved under `sim/build/<target>/target.json`.

### Phase 3A -- Normal Conv

Tasks:
- Write Python golden model in `scripts/golden_eg2c.py`.
- Implement or extend `rtl/eg2c_dense_conv2d.v`.
- Define a small test shape, for example `H=4, W=4, Cin=2, Cout=3, K=3`.
- Implement a simple normal-conv schedule. It may use fewer lanes than the final optimized paper mapping.

Verification:
- `./sim/run_sim.sh conv`

Acceptance:
- Normal convolution matches Python golden on the toy tensor.

### Phase 3B -- Depth-Wise Conv

Tasks:
- Add depth-wise golden support.
- Implement or extend `rtl/eg2c_dw_conv2d.v`.
- Define a small test shape, for example `H=4, W=4, C=4, K=3`.
- Implement a simple one-output-at-a-time depth-wise schedule.

Verification:
- `./sim/run_sim.sh dw`

Acceptance:
- Depth-wise convolution matches Python golden on the toy tensor.

### Phase 3C -- Point-Wise Conv

Tasks:
- Add point-wise golden support.
- Implement or extend `rtl/eg2c_pw_conv2d.v`.
- Define a small test shape, for example `H=4, W=4, Cin=4, Cout=5`.
- Implement a simple `1x1` schedule.

Verification:
- `./sim/run_sim.sh pw`

Acceptance:
- Point-wise convolution matches Python golden on the toy tensor.

### Phase 3D -- Average Pooling

Tasks:
- Add average-pooling golden support.
- Define a detector-style pooling target, for example `H=4, W=4, C=1, pool=4x4`.
- Define integer division rounding before implementation; default is truncate toward zero.

Verification:
- `./sim/run_sim.sh pool`

Acceptance:
- Pooling matches Python golden on the toy tensor.

## Phase 4 -- Instruction-Driven Layer Scheduling

Goal:
- Let a compact dense-pipeline model execute a list of layer instructions instead of hard-coded testbench steps.

Tasks:
- Define the minimal simulation opcodes and document them.
- Implement `eg2c_dense_pipeline` states:
  - idle;
  - fetch instruction;
  - decode;
  - wait for CONV;
  - wait for POOL;
  - done.
- Reject unsupported opcodes with `error_o`.
- Add generated programs that cover:
  - `CONV -> POOL -> DONE`;
  - `DONE` only;
  - `NOP -> CONV -> POOL -> DONE`;
  - illegal opcode/error.
- Keep detector/coarse/precise top-level sequencing for later `top` integration work.

Verification:
- Python script generates:
  - instruction memory hex;
  - weight memory hex;
  - activation input hex;
  - expected output hex;
  - per-case expected `error_o`, `op_count_o`, and `cycle_count_o`.
- Testbench loads all artifacts and starts `eg2c_dense_pipeline` once per generated program.

Acceptance:
- `./sim/run_sim.sh pipeline_dense` runs all generated dense toy programs and reports PASS.
- This is the first integration milestone, not the first executable milestone.

## Phase 5 -- Detector Branching

Goal:
- Model e-G2C's event-driven coarse/precise selection.

Tasks:
- Implement detector output compare against threshold.
- If detector result is normal, run coarse converter instruction range.
- If detector result is abnormal, run precise converter instruction range.
- Add observable status signals:
  - selected path;
  - detector score;
  - threshold;
  - cycle count.

Verification:
- One test input forces normal path.
- One test input forces abnormal path.

Acceptance:
- `./sim/run_sim.sh branch` reports PASS for both paths.

## Phase 6 -- Vector-Wise Sparse Mode

Goal:
- Reproduce the paper's vector-wise sparse processing at architecture level.

Paper behavior:
- Normal Conv: one sparse vector corresponds to one row of weights.
- Point-wise Conv: one sparse vector corresponds to three weights.
- Index SRAM selects the proper activation rows/elements.

Tasks:
- Define compressed vector format.
- Define index format.
- Implement `eg2c_sparse_selector.v`.
- Implement an architecture-level sparse vector MAC target.
- Add sparse mode to normal conv and point-wise conv schedules.
- Count skipped vectors and active MAC cycles.

Verification:
- Generate a dense weight tensor.
- Compress it into vector-wise sparse format.
- Run dense and sparse RTL on the same input.
- Compare both RTL results to Python golden.

Acceptance:
- Sparse vector-MAC output equals dense dot-product output.
- Simulated active work decreases on sparse test cases.
- Sparse normal-conv and point-wise-conv schedule outputs equal dense Python golden output.
- Sparse normal-conv and point-wise-conv schedule counters show lower total cycles than the dense-equivalent schedules.

## Phase 7 -- Depth-Wise Conv Reuse Modes

Goal:
- Add architecture-level simple, CIR, and D-RIR lane-assignment schedules for depth-wise convolution.
- Verify output equivalence against the simple dense DW golden output.

Paper behavior:
- CIR maps one input activation row to three MAC lanes for three output rows.
- D-RIR splits one input row into two sub-rows and maps them to two MAC lanes.
- The RTL model below preserves the D-RIR two-lane reuse idea with adjacent output-column lanes; it does not claim an ASIC-exact Fig. 4 cycle table.

Tasks:
- Keep the simple DW Conv target as a baseline reference.
- Implement explicit lane-assignment schedules:
  - `simple`: one output/kernel term lane per cycle;
  - `cir`: one input activation position and one kernel column feed `K_H` output-row lanes;
  - `d_rir`: one output row/kernel term feeds two adjacent output-column lanes.
- Run the three schedules in the `dw_reuse` wrapper and expose simple/CIR/D-RIR outputs.
- Track cycle, active-lane, and idle-lane counters for each mode.
- Emit a per-cycle schedule trace for each mode so tests can catch lane-order regressions, not only aggregate counter regressions.

Verification:
- Same input/weights through simple, CIR, and D-RIR DW schedules.
- All three output tensors must match Python golden.
- Simple/CIR/D-RIR counters must match generated expected stats.
- Simple/CIR/D-RIR per-cycle traces must match generated schedule traces.
- CIR and D-RIR cycle counts must be lower than the simple schedule on the generated target.

Acceptance:
- `./sim/run_sim.sh dw_reuse` reports PASS and prints cycle, active-lane, and idle-lane counts.

## Phase 8 -- Threshold Adaptation Engine

Goal:
- Reproduce the on-chip adaptation flow in Fig. 6.

Parameters to freeze before coding:
- Detector score format: signed 8-bit for the first test.
- Threshold format: signed 8-bit.
- Histogram interval count: default `8`.
- Counter width: default `16` bits.
- Sensitive range: default `[-64, 64]`, represented by interval boundaries in a generated `adapt_target.json`.
- Interval rule: lower bound inclusive, upper bound exclusive, except the last interval includes its upper bound.
- Midpoint rule: integer midpoint truncating toward zero.
- Start rule: `start_i` is accepted only on a rising edge while the engine is idle.
- Update/sample rule: if `update_i` and `score_valid_i` are asserted together, that score is counted before argmin and the histogram snapshot.
- Counter overflow rule: histogram counters saturate at their maximum value instead of wrapping.
- Update cadence: the testbench triggers update after a finite sample window, standing in for the paper's multi-day `T` window.

Tasks:
- Implement interval comparison through `boundaries.hex`.
- Implement histogram counters, accepted-sample count, and ignored out-of-range sample count.
- Implement argmin tree with the frozen tie rule: lowest interval index wins equal minimum counts.
- Implement threshold update to the midpoint of the least-occurrence interval.
- Add reset of live histogram counters after update while preserving a pre-reset snapshot for verification.
- Add a restart case to prove a second adaptation window does not reuse stale counters.
- Add held-start, same-cycle update/sample, single-cycle `done_o`, and counter-saturation checks.

Verification:
- Feed deterministic detector score windows generated by `scripts/golden_eg2c.py adapt`.
- Compare live histogram counters before update, histogram snapshot after update, final threshold, selected interval, accepted sample count, ignored sample count, and reset live counters to Python golden.
- Cover interval boundary rules, out-of-range ignored samples, lower-index argmin tie-break, a second restarted update window, held `start_i`, update/sample coincidence, and saturated counter behavior.

Acceptance:
- `./sim/run_sim.sh adapt` reports PASS.

## Phase 9 -- Integrated e-G2C Toy System

Goal:
- Run an end-to-end architecture-level toy system:
  - detector;
  - threshold decision;
  - coarse or precise converter;
  - optional threshold adaptation update.

Implemented scope:
- `rtl/eg2c_integrated_top.v` connects:
  - `eg2c_detector_branch` for signed score-vs-threshold path selection;
  - one coarse and one precise `eg2c_dense_pipeline`, with only the selected path started;
  - `eg2c_adapt_engine` for an optional co-running threshold update for future windows.
- `tb/tb_top.v` runs three generated cases:
  - normal/coarse path;
  - abnormal/precise path with threshold adaptation;
  - abnormal/precise path with an illegal converter opcode.
- `scripts/golden_eg2c.py top` writes all memory/control images and expected status files under `sim/build/top/`.
- The top target prints:
  - selected path;
  - cycle count;
  - sparse skipped count;
  - output mismatch count.

Current limitation:
- The integrated top target uses dense converter paths. Sparse-skip reporting is plumbed and expected to be zero in this target; standalone sparse behavior remains verified by `sparse`, `conv_sparse`, and `pw_sparse`.
- The legacy `rtl/eg2c_top.v` remains a smoke-shell memory/controller wrapper; `rtl/eg2c_integrated_top.v` is the implemented architecture-level integration target.

Acceptance:
- `./sim/run_sim.sh top` reports PASS for normal and abnormal scenarios.

## Phase 10 -- Documentation And Cleanup

Goal:
- Make the implementation understandable and maintainable.

Tasks:
- Update `PROJECT_GUIDE.md` with actual module names and examples.
- Update `PAPER_NOTES.md` with any new assumptions discovered.
- Update `TODO.md` to reflect remaining work.
- Record bugs in `BUGFIX.md`.
- Keep generated files under `build/`, `sim/build/`, or `e-G2C/extracted/`.

Acceptance:
- A fresh checkout can run the documented simulation command.
- The top-level guide explains the current implemented scope honestly.

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Paper omits exact instruction encoding | Cannot reproduce bit-exact control format | Define a clean 32-bit-compatible simulation encoding and document it |
| No real weights or data | Cannot reproduce accuracy | Use deterministic toy data for architecture verification |
| Quantization details are missing | Arithmetic may differ from chip | Start with signed integer arithmetic; make quantization a documented parameter |
| Sparse packing format is missing | Cannot know exact memory layout | Implement a reasonable vector-wise format matching Fig. 3 behavior |
| DW reuse schedule is only shown graphically | Exact cycles may differ | Verify output correctness and project-local per-cycle traces, then report simulated utilization trends |
| GTKWave has no DISPLAY in this shell | Cannot open GUI from automation | Generate VCD files; user can open them in a graphical terminal |

## First Executable Milestone

The first executable milestone is:

```bash
./sim/run_sim.sh smoke
```

It should:
- compile the minimal RTL skeleton;
- load tiny memory images through testbench backdoors;
- start the top-level controller;
- observe `done`;
- print PASS.

The first integration milestone is:

```bash
./sim/run_sim.sh pipeline_dense
```

It currently runs compact dense toy programs, including CONV -> POOL -> DONE, DONE-only, NOP-prefixed, and illegal-opcode cases, without sparse optimization.

The top integration milestone is:

```bash
./sim/run_sim.sh top
```

It runs generated normal/coarse, abnormal/precise-with-adaptation, and abnormal/precise-illegal-opcode scenarios through `eg2c_integrated_top`. Sparse mode, the DW reuse lane scheduler, and threshold adaptation were added after the dense pipeline milestone. Sparse weight-vector skipping is integrated into standalone normal-conv and point-wise-conv schedulers; DW simple/CIR/D-RIR lane-assignment schedules run in `dw_reuse`; the Fig. 6 adaptation loop runs in both standalone `adapt` and integrated `top` form.
