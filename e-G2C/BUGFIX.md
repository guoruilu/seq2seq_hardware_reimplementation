# BUGFIX

Bug records use this format:

```text
## #NNN -- short title

Symptoms:
Root cause:
Fix:
Prevention:
```

## #001 -- Function-hidden vector sensitivity in combinational datapaths

Symptoms:
- `./sim/run_sim.sh pipeline_dense` initially failed only on `output[0]`.
- Standalone `conv` and standalone `pool` both passed with the same generated data.

Root cause:
- The pool module read `input_act_i` through a helper function inside `always @(*)`.
- In Icarus Verilog, that indirect vector read was not reliably included in the inferred sensitivity set, so the first pool accumulation used a stale value after `conv_output` changed.

Fix:
- Replaced the affected arithmetic modules' inferred `always @(*)` blocks with explicit sensitivity lists that include `input_act_i` and `weight_i` where relevant.

Prevention:
- For simulation datapaths that use helper functions to index large flattened vectors, explicitly include dynamic input vectors in the combinational sensitivity list or compute directly in sequential code.

## #002 -- Non-root simulation invocation could falsely pass

Symptoms:
- Running `/path/to/repo/sim/run_sim.sh conv` from outside the repository root caused `$readmemh` file-open errors.
- Despite missing input/golden files, the test could still print `PASS` with exit code 0 because uninitialized values were not checked before use.

Root cause:
- `sim/run_sim.sh` generated artifacts under an absolute `sim/build/<target>/` path but launched `vvp` from the caller's working directory.
- Testbenches used repository-relative paths such as `sim/build/conv/input_act.hex`.
- Testbenches did not validate loaded memories for X/Z values before running.

Fix:
- `sim/run_sim.sh` now changes to the repository root before compilation/simulation and rejects extra arguments.
- Testbenches that load generated files now check loaded arrays for X/Z before packing or comparing data.

Prevention:
- Keep simulation file paths rooted at one working directory.
- Add load-integrity checks whenever a testbench consumes `$readmemh`/`$readmemb` artifacts.

## #003 -- Branch test did not distinguish signed from unsigned comparison

Symptoms:
- The detector branch target claimed signed `score >= threshold` semantics.
- The generated cases had the same expected result under signed and unsigned comparison.

Root cause:
- The branch golden vectors covered normal, abnormal, and equality cases, but not mixed-sign cases.

Fix:
- Added branch cases `score=-1, threshold=1` and `score=1, threshold=-1`, which fail under the wrong signedness.
- Added waveform support to `tb_branch`.

Prevention:
- Every signed comparison test should include at least one mixed-sign case where signed and unsigned results differ.

## #004 -- Top controller skipped invalid or unterminated programs

Symptoms:
- RTL review found that the smoke/top-shell controller treated any opcode except `NOP` and `DONE` as a one-cycle runnable operation.
- Programs without a reachable `DONE` could advance until the instruction address wrapped.

Root cause:
- `eg2c_controller` did not have an opcode whitelist, `error_o`, or an instruction-count guard.

Fix:
- Added opcode validation, `error_o`, and `INSTR_COUNT` bounds checking to `eg2c_controller`.
- Exposed the error signal through `eg2c_top`.
- Extended `tb_smoke` with direct controller checks for invalid opcode and missing-DONE timeout cases.

Prevention:
- Every instruction walker should have explicit illegal-instruction and program-bound tests, even while it is still a smoke-shell model.

## #005 -- Single pipeline program allowed instruction-driven false positives

Symptoms:
- Test/golden review found that `pipeline_dense` could pass even if the DUT ignored `instr_mem` and hard-coded CONV then POOL.

Root cause:
- The generated target contained only one program: `CONV -> POOL -> DONE`.

Fix:
- Expanded `pipeline_dense` golden data to four programs: normal CONV/POOL, DONE-only, NOP-prefixed CONV/POOL, and illegal opcode.
- Added per-case `expected_status.hex` checks for `error_o`, `op_count_o`, and `cycle_count_o`.
- Added `manifest.json` plus manifest validation for generated artifact line counts and hashes.

Prevention:
- Instruction-driven tests must include at least one no-op path, one shifted legal path, and one illegal path.
