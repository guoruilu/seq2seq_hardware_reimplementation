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
```

`golden_eg2c.py` writes deterministic `sim/build/<target>/` artifacts:
`input_act.hex`, `weights.hex`, `expected.hex`, and `target.json`.
