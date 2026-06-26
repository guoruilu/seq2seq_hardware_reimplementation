# LOG

Each entry should be 1-3 lines: date, change, current status.

- 2026-06-26: Read `2022_VLSI_e-G2C.pdf` and `guide_ref/` documents. Scope set to architecture-level Verilog simulation first, with no real weights/dataset available.
- 2026-06-26: User confirmed external research is allowed, e-G2C-specific docs should live under `e-G2C/`, and generic reimplementation docs should live at repo root.
- 2026-06-26: Verified installed tools: `iverilog`, `vvp`, `pdftotext`, `pdfimages`; `gtkwave` is installed but needs a graphical DISPLAY to open waveforms.
- 2026-06-26: Added initial documentation set: root reimplementation guide, e-G2C paper notes, project guide, implementation plan, TODO, and BUGFIX.
- 2026-06-26: Independent plan-review subagent found the first milestone too large and several contracts unclear. Revised the plan with explicit path conventions, generated artifact formats, smaller milestones, Phase 3 subphases, and an assumption register.
- 2026-06-26: Independent reviewer accepted the revised plan with no blocking findings. Addressed remaining small notes by adding `target.json`/`adapt_target.json` to the artifact contract, clarifying `expected.hex`, and aligning TODO with the Phase 4 dense pipeline.
- 2026-06-26: Extracted paper text to `e-G2C/extracted/paper_text.txt` and rendered local page images under `e-G2C/extracted/pages/`. Added extraction manifest and local figure lookup notes; page PNGs remain ignored by Git.
- 2026-06-26: Added the minimal RTL/simulation skeleton: paper-sized behavioral memories, pass-through activation buffers, MAC lane/array modules, controller/top shells, `tb_smoke`, and `sim/run_sim.sh smoke`. Smoke simulation passes.
- 2026-06-26: Added `tb_mac` and the `./sim/run_sim.sh mac` target for signed MAC lane accumulation, clear behavior, and 32-lane array arithmetic. Smoke and MAC simulations pass.
- 2026-06-26: Added deterministic Python golden generation plus `eg2c_dense_conv2d`, `tb_conv`, and `./sim/run_sim.sh conv` for the first dense normal-convolution baseline. Conv target uses NHWC activations, `kh,kw,cin,cout` weights, explicit zero padding, signed int8 data/weights, int32 accumulation, and saturated int8 output.
- 2026-06-26: Added depth-wise convolution golden generation plus `eg2c_dw_conv2d`, `tb_dw`, and `./sim/run_sim.sh dw`. DW target matches Python golden with one kernel element per simulated cycle.
- 2026-06-26: Added point-wise convolution golden generation plus `eg2c_pw_conv2d`, `tb_pw`, and `./sim/run_sim.sh pw`. PW target uses `cin,cout` 1x1 weights and matches Python golden.
- 2026-06-26: Added average-pooling golden generation plus `eg2c_avg_pool2d`, `tb_pool`, and `./sim/run_sim.sh pool`. Pool target uses 2x2 stride-2 signed average with truncation toward zero.
