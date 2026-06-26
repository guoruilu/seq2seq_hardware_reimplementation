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
