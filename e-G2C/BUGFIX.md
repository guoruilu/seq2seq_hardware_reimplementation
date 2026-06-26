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

## #006 -- DW reuse wrapper accepted unsynchronized child starts

Symptoms:
- Independent RTL review found that a held or repeated `start_i` could restart shorter DW reuse schedules while the longer simple schedule was still running.
- CIR and D-RIR finish earlier than simple on the generated target, so forwarding raw `start_i` let those children accept a new operation independently.

Root cause:
- `eg2c_dw_reuse_conv2d` forwarded the top-level `start_i` directly to the simple, CIR, and D-RIR child schedulers.
- The wrapper also cleared done-seen state on any asserted `start_i`, even when not all children accepted the same operation.

Fix:
- Added wrapper-level start-edge gating and fan out only one synchronized child start pulse while the wrapper is idle.
- Changed wrapper `busy_o` to stay asserted for the whole aggregate operation until the wrapper emits `done_o`.
- Extended `tb_dw_reuse` to hold `start` high until `done`, which catches independent child restarts.

Prevention:
- Multi-engine wrappers should own the transaction handshake and should never pass raw level-sensitive starts to children with different latencies.
- Stress tests should include held-start or repeated-start cases for any wrapper that coordinates multiple child engines.

## #007 -- Adaptation engine accepted ambiguous control edges

Symptoms:
- Independent RTL/test review found that a held `start_i` could restart the adaptation engine immediately after `done_o`, clearing the updated threshold and histogram snapshot.
- If `update_i` and `score_valid_i` arrived in the same cycle, the final detector score could be dropped from the histogram before argmin.
- Histogram counters incremented with natural wraparound when full.
- The first adaptation testbench used truthy checks for `busy`/`done`, so X/Z control values could be missed.

Root cause:
- `eg2c_adapt_engine` accepted level-sensitive starts in `STATE_IDLE`.
- The RUN state prioritized update over score ingestion.
- Counter increment logic did not define overflow behavior.
- The testbench checked control signals with logical negation instead of case equality and did not stress held-start or same-cycle update/sample behavior.

Fix:
- Added rising-edge start acceptance while idle.
- Changed update to use the post-sample histogram when `update_i` and `score_valid_i` are asserted together.
- Changed histogram counters to saturate at their maximum value.
- Extended `tb_adapt` with case-equality control checks, one-cycle `done_o` checking, held-start stress, same-cycle update/sample coverage, and a small-width saturation DUT.

Prevention:
- Every control-oriented testbench should use case equality for one-bit status checks.
- Every start/done handshake should include held-start or repeated-start stress.
- Counter modules should document and test overflow behavior before integration.

## #008 -- Integrated top used ambiguous transaction inputs

Symptoms:
- Independent RTL/test review found that `eg2c_integrated_top` accepted level-sensitive `start_i`, so a held start could relaunch immediately after `done_o`.
- The top used live `adapt_enable_i` and `adapt_score_count_i` during RUN, so host-side input changes could stop score feeding and leave the adaptation child mid-transaction.
- Converter error paths could expose stale child output from a previous transaction.
- `eg2c_dense_pipeline` allowed `POOL` before any current-transaction `CONV`, which could consume stale convolution output.

Root cause:
- The first top integration treated control inputs as stable levels rather than start-latched transaction fields.
- Top outputs forwarded child state without a per-transaction validity/reset policy.
- The dense pipeline did not track whether its current transaction had produced a valid convolution result before pooling.

Fix:
- Added rising-edge start acceptance in `eg2c_integrated_top`.
- Latched adaptation enable/count/window inputs at transaction start.
- Registered top adaptation outputs per transaction and cleared them on new starts.
- Forced selected top output to zero on converter errors.
- Added held-start, no-reset stale-output, precise/coarse illegal-opcode, invalid-adaptation-length, and mutated-live-adaptation-input coverage to `tb_top`.
- Added a current-transaction `conv_output_valid` guard to `eg2c_dense_pipeline` and a generated `pool_before_conv` error case.

Prevention:
- Top-level wrappers should latch transaction control fields at start rather than sampling live host inputs during RUN.
- Error-path tests should run at least one case without reset after a successful case to catch stale outputs.
- Instruction-driven tests should include dependency-order errors, not only illegal opcodes.
