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
