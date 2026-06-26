# Reimplementation Guide

> This document is the shared engineering rulebook for this repository. Paper-specific notes and task plans live under each paper directory, for example `e-G2C/`.

## 1. Current Scope

The current task is to reimplement the e-G2C paper at an architecture-simulation level in Verilog.

This means:
- Build RTL modules that reflect the paper's processor organization and dataflows.
- Provide deterministic test data, Python golden references, and Icarus Verilog testbenches.
- Verify functional behavior and scheduling at small, practical tensor sizes first.

This does not mean, for the current phase:
- Reproducing the 28 nm ASIC physical implementation.
- Reproducing measured power, area, or energy numbers.
- Matching the paper's clinical accuracy without the original model weights, datasets, and training pipeline.

## 2. Directory Rules

Generic reimplementation documents stay in the repository root:
- `REIMPLEMENTATION_GUIDE.md`: shared rules and workflow.

Paper-specific documents stay next to that paper:
- `e-G2C/PROJECT_GUIDE.md`: beginner-friendly guide for the e-G2C implementation.
- `e-G2C/PAPER_NOTES.md`: extracted paper facts, assumptions, and open details.
- `e-G2C/IMPLEMENTATION_PLAN.md`: detailed execution plan.
- `e-G2C/TODO.md`: short current task list.
- `e-G2C/LOG.md`: concise progress log.
- `e-G2C/BUGFIX.md`: bug records and prevention notes.

The `guide_ref/` directory is a reference from an earlier project. Do not edit it unless explicitly asked.

## 3. Work Discipline

Every meaningful change should update documents in the same turn:
- Update `e-G2C/LOG.md` with what changed and the current status.
- Update `e-G2C/TODO.md` when priorities change or tasks complete.
- Update `e-G2C/BUGFIX.md` when a bug is found and fixed.
- Update `e-G2C/PROJECT_GUIDE.md` or `e-G2C/IMPLEMENTATION_PLAN.md` when architecture, module boundaries, or verification strategy changes.

Every completed small task should be committed and pushed to the configured GitHub remote before starting the next task.

Every completed large task must go through independent review before the next large task starts:
- documentation consistency;
- RTL/architecture code;
- golden data and testbench checks;
- simulation flow and generated artifacts.

Fix review findings, rerun regression, update documents, commit, push, and repeat independent review until the loop converges.

Keep logs short. Put detailed reasoning in the guide or plan, not in the log.

## 4. RTL Rules

Use parameterized Verilog for paper-derived constants:
- Data width, weight width, accumulator width.
- MAC lane count.
- Memory sizes.
- Tensor dimensions used by tests.
- Instruction field widths.

Do not hard-code paper numbers deep inside modules. Put them in `rtl/eg2c_defines.vh` or module parameters.

For vendor/IP-like blocks, add a file header:

```verilog
// [IP] <IP name or hardware block> -- from paper <Fig./Sec.>.
//   Behavioral implementation: YES / NO.
//   Notes: <how this RTL models or stubs the paper block>.
```

Behavioral RAMs and multipliers are acceptable for simulation. If a block would become SRAM, SRAM macro, or DSP in silicon, document that in the file header and in `e-G2C/IMPLEMENTATION_PLAN.md`.

## 5. Verification Rules

Every RTL module that transforms data needs a matching test:
- Small deterministic input.
- Python golden reference when arithmetic or address mapping is non-trivial.
- Icarus Verilog testbench.
- A clear PASS/FAIL summary.

Preferred simulation flow:

```bash
./sim/run_sim.sh <target>
```

Initial targets should be small and fast:
- RAM smoke tests.
- MAC lane tests.
- Dense convolution tests.
- Sparse vector selection tests.
- Threshold adaptation tests.
- Top-level toy pipeline tests.

The current implemented full regression is:

```bash
./sim/run_sim.sh all
```

It includes the architecture-level integrated top target.

Waveform support is useful but not required for every run. If a test supports waves, use a `wave` option and generate a VCD file under `build/` or `sim/build/`.

## 6. Documentation Style

Write documents for a Verilog beginner who has written UART/SPI/simple FSMs, but has not built a neural-network accelerator.

For each new concept:
- Start with a plain-language analogy.
- Then define the hardware or algorithmic term.
- Explain why this block exists.
- Show what it connects to.
- Give one concrete data example.

Use tables and ASCII diagrams where they make the dataflow clearer.

## 7. Tooling

Expected local tools:
- `iverilog` and `vvp` for Verilog simulation.
- `gtkwave` for optional waveform viewing.
- `pdftotext` and `pdfimages` for paper extraction.
- Python 3 for data generation and golden models.

If a tool is missing, keep working with available alternatives when practical. For PDF extraction, PyMuPDF is also acceptable.
