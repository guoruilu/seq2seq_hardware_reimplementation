# Scripts

Python generators and golden-reference checkers live here.

Current executable flow:

```sh
./sim/run_sim.sh smoke
./sim/run_sim.sh mac
./sim/run_sim.sh conv
./sim/run_sim.sh dw
./sim/run_sim.sh pw
./sim/run_sim.sh pool
./sim/run_sim.sh pipeline_dense
./sim/run_sim.sh branch
./sim/run_sim.sh sparse
./sim/run_sim.sh dw_reuse
```

`golden_eg2c.py` writes deterministic `sim/build/<target>/` artifacts. Common files are:

| File | Used by |
|---|---|
| `input_act.hex` | activation-based targets |
| `weights.hex` | convolution, sparse, and DW reuse targets |
| `expected.hex` | all golden-checked targets |
| `target.json` | all generated targets |
| `instr.hex` | `pipeline_dense` |
| `scores.hex`, `thresholds.hex`, `expected_path.bin` | `branch` |
| `indices.hex`, `vector_valid.bin`, `expected_stats.hex` | `sparse` |
| `expected_stats.hex` | `dw_reuse` |

All files under `sim/build/` are generated and disposable.
