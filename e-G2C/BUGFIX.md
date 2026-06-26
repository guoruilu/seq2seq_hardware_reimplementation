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
