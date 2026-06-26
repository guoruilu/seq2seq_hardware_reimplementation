# Scripts

Python generators and golden-reference checkers live here.

Current executable flow:

```sh
./sim/run_sim.sh all
./sim/run_sim.sh smoke
./sim/run_sim.sh mac
./sim/run_sim.sh conv
./sim/run_sim.sh dw
./sim/run_sim.sh pw
./sim/run_sim.sh pool
./sim/run_sim.sh pipeline_dense
./sim/run_sim.sh branch
./sim/run_sim.sh sparse
./sim/run_sim.sh conv_sparse
./sim/run_sim.sh pw_sparse
./sim/run_sim.sh dw_reuse
./sim/run_sim.sh adapt
```

`golden_eg2c.py` writes deterministic `sim/build/<target>/` artifacts. The project does not currently keep checked-in `data/golden/` fixtures; generated files are verified through `manifest.json` line counts and hashes. Common files are:

| File | Used by |
|---|---|
| `input_act.hex` | activation-based targets |
| `weights.hex` | convolution, sparse, and DW reuse targets |
| `expected.hex` | activation-producing golden targets; `adapt` uses `expected_histogram.hex` and `expected_stats.hex` instead |
| `target.json` | all generated targets |
| `adapt_target.json` | `adapt` |
| `manifest.json` | generated target integrity checks before simulation |
| `instr.hex`, `expected_status.hex` | `pipeline_dense` |
| `scores.hex`, `thresholds.hex`, `coarse.hex`, `precise.hex`, `expected_path.bin` | `branch` |
| `scores.hex`, `boundaries.hex`, `initial_thresholds.hex`, `case_lengths.hex`, `expected_histogram.hex`, `expected_stats.hex` | `adapt` |
| `indices.hex`, `vector_valid.bin`, `expected_stats.hex` | `sparse` |
| `vector_valid.bin`, `expected_stats.hex` | `conv_sparse`, `pw_sparse` |
| `expected_stats.hex`, `simple_trace.hex`, `cir_trace.hex`, `drir_trace.hex` | `dw_reuse` |

All files under `sim/build/` are generated and disposable.

Target-specific field order:

| File | Target | Field Order |
|---|---|---|
| `expected_status.hex` | `pipeline_dense` | repeated per case: `expected_error`, `expected_ops`, `expected_cycles` |
| `expected_stats.hex` | `sparse` | `dense_accumulator`, `active_sparse_cycles`, `skipped_vectors`, `dense_equivalent_cycles`, `total_sparse_cycles` |
| `expected_stats.hex` | `conv_sparse`, `pw_sparse` | `dense_equivalent_cycles`, `active_sparse_cycles`, `skipped_vectors`, `total_sparse_cycles` |
| `expected_stats.hex` | `dw_reuse` | `simple_cycles`, `cir_cycles`, `drir_cycles`, `simple_active_slots`, `cir_active_slots`, `drir_active_slots`, `simple_idle_slots`, `cir_idle_slots`, `drir_idle_slots` |
| `expected_stats.hex` | `adapt` | repeated per case: `updated_threshold`, `selected_interval`, `accepted_samples`, `ignored_samples`, `total_samples` |
| `expected_histogram.hex` | `adapt` | repeated per case: one counter per interval, using the interval order in `boundaries.hex` |

For `branch`, `expected.hex` is the selected output vector after applying `expected_path.bin` to choose each case's `coarse.hex` or `precise.hex` vector.
