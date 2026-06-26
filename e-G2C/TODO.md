# TODO

> Keep this file short. Detailed reasoning belongs in `IMPLEMENTATION_PLAN.md`.

## P0 -- Documents And Paper Extraction

- [x] Verify installed tools: `iverilog`, `vvp`, `pdftotext`, `pdfimages`, `gtkwave`.
- [x] Add initial project guide, paper notes, implementation plan, TODO, LOG, and BUGFIX.
- [x] Extract paper text to `e-G2C/extracted/paper_text.txt`.
- [x] Extract rendered page images to `e-G2C/extracted/pages/` for local inspection.
- [x] Add `e-G2C/extracted/README.md` with extraction commands and file list.
- [x] Add local page-image references to `PAPER_NOTES.md`.
- [ ] Crop key figure images from rendered pages if needed during RTL implementation.
- [ ] Record any external sources before using them for implementation assumptions.

## P1 -- Skeleton And Arithmetic Milestones

- [x] Create `rtl/`, `tb/`, `sim/`, and `scripts/`.
- [x] Add `eg2c_defines.vh`.
- [x] Implement behavioral memories.
- [x] Implement pass-through `eg2c_input_act_buffer.v` and `eg2c_output_act_buffer.v`.
- [x] Implement MAC lane and MAC array.
- [x] Add `sim/run_sim.sh` with `smoke` and `wave` support.
- [x] Run `./sim/run_sim.sh smoke`.
- [ ] Add `mac` target to `sim/run_sim.sh`.
- [ ] Run `./sim/run_sim.sh mac`.

## P2 -- Dense Operation Baseline

- [ ] Freeze Phase 3 assumptions in generated `target.json`: layout, padding, stride, activation, saturation.
- [ ] Implement Python generator/golden contract under `scripts/`.
- [ ] Implement dense normal conv toy test: `./sim/run_sim.sh conv`.
- [ ] Implement dense depth-wise conv toy test: `./sim/run_sim.sh dw`.
- [ ] Implement dense point-wise conv toy test: `./sim/run_sim.sh pw`.
- [ ] Implement average-pooling toy test: `./sim/run_sim.sh pool`.

## P2.5 -- Instruction Pipeline

- [ ] Implement instruction-driven dense toy pipeline: `./sim/run_sim.sh pipeline_dense`.

## P3 -- e-G2C Features

- [ ] Add detector branch to coarse/precise path.
- [ ] Add vector-wise sparse normal/PW conv mode.
- [ ] Add DW Conv CIR and D-RIR scheduling modes.
- [ ] Add threshold adaptation engine.
- [ ] Add top-level integrated toy system regression: `./sim/run_sim.sh top`.

## P4 -- Cleanup

- [ ] Update project guide with actual RTL module details.
- [ ] Keep generated files under `sim/build/` or `e-G2C/extracted/`.
- [ ] Record implementation bugs in `BUGFIX.md`.
