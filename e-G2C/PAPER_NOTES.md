# e-G2C Paper Notes

> Source: `2022_VLSI_e-G2C.pdf`.
>
> Goal of this document: capture the facts that drive the Verilog architecture, and clearly separate paper facts from implementation assumptions.

## 1. One-Sentence Summary

e-G2C is a dedicated neural-network processor for pacemaker remote monitoring. It performs lightweight anomaly detection all the time, then uses either a coarse or precise EGM-to-ECG converter depending on whether the current heartbeat looks normal or abnormal.

## 2. System Pipeline

Plain-language view:

The chip behaves like a triage desk. A small detector checks every heartbeat first. If the heartbeat looks normal, the chip runs a cheaper converter. If it looks abnormal, the chip runs a more expensive converter that produces richer ECG output.

Paper pipeline:

```text
Analog frontend
      |
      v
Detector + adaptive threshold
      |
      +-- normal   --> 1-channel coarse converter
      |
      +-- abnormal --> 4-channel precise converter
```

The detector and converters share one NN engine through time multiplexing.

## 3. Processor Blocks From Fig. 2

| Block | Paper fact | Architecture-level RTL plan |
|---|---:|---|
| Instruction SRAM | 4 KB, 32-bit instructions | `eg2c_instr_mem.v`, behavioral SRAM |
| Weight global buffer | 1-bank 32 KB | `eg2c_weight_mem.v`, stores dense or compressed weights |
| Index SRAM | 1-bank 10 KB | `eg2c_index_mem.v`, stores sparse vector indices |
| Activation GB0 | 2-bank 25 KB | `eg2c_act_mem.v`, ping-pong input/output role |
| Activation GB1 | 2-bank 25 KB | same module, second instance |
| Input Act Buffer | prepares selected activation rows | `eg2c_input_act_buffer.v` |
| Output Act Buffer | collects MAC outputs | `eg2c_output_act_buffer.v` |
| MAC lanes | 32 lanes shown; each lane contains multiple MAC elements in Fig. 2 | `eg2c_mac_lane.v` and `eg2c_mac_array.v` |
| Adaptation engine | comparator, histogram counters, argmin, threshold registers | `eg2c_adapt_engine.v` |
| Controller | reads 32-bit instructions and drives the shared engine | `eg2c_controller.v` |

Paper measurement numbers:
- Process: 28 nm.
- Memory: 104 KB.
- Frequency: 2 MHz.
- Power: 430 uW.
- Energy: 0.14 uJ/detection, 4.13 uJ/coarse conversion, 8.31 uJ/precise conversion.
- Latency: 0.32 ms/detection, 9.62 ms/coarse conversion, 13.32 ms/precise conversion.

These are measurement targets for context only. The Verilog simulation will not claim to reproduce ASIC energy or area.

## 4. Models From Fig. 5

### Detector

Input:
- 4-channel EGM signals.

Layers shown:

| Layer | Shape in paper |
|---|---|
| Conv | `3 x 3 x 28 x 1` |
| Average Pooling | `4 x 4` |
| Threshold | normal/abnormal decision |

Paper-reported accuracy:
- 95.1% +/- 4.0% among 14 patients.
- Weight size: 0.09 KB.

### Coarse Converter

Input:
- 1-channel EGM signals.

Layers shown:

| Layer | Shape in paper |
|---|---|
| Conv | `3 x 3 x 2 x 32` |
| Depth-wise Conv | `3 x 3 x 32` |
| Point-wise Conv | `1 x 1 x 32 x 32` |
| Conv | `3 x 3 x 32 x 24` |

Output:
- 12-channel ECG signals.

Paper-reported accuracy:
- 94.0% +/- 2.5%.
- Weight size: 4.38 KB.

### Precise Converter

Input:
- 4-channel EGM signals.

Layers shown:

| Layer | Shape in paper |
|---|---|
| Conv | `3 x 3 x 8 x 16` |
| Depth-wise Conv | `3 x 3 x 16` |
| Point-wise Conv | `1 x 1 x 16 x 32` |
| Depth-wise Conv | `3 x 3 x 32` |
| Point-wise Conv | `1 x 1 x 32 x 64` |
| Depth-wise Conv | `3 x 3 x 64` |
| Point-wise Conv | `1 x 1 x 64 x 64` |
| Conv | `3 x 3 x 64 x 24` |

Output:
- 12-channel ECG signals.

Paper-reported accuracy:
- 96.9% +/- 1.7%.
- Weight size: 9.13 KB.

## 5. Sparse Processing From Fig. 3

Plain-language view:

Instead of carrying a full basket of weights where many entries are zero, the chip carries only useful small groups plus a note saying where each group belongs.

Paper idea:
- One sparse vector corresponds to one row of weights in normal convolution.
- One sparse vector corresponds to three weights in point-wise convolution.
- Index SRAM tells the activation selector which activation rows/elements should feed each MAC lane.
- Skipping sparse vectors reduces work and energy.

Architecture-level plan:
- First implement dense convolution so the math and memory layout are correct.
- Add sparse vector mode in two steps:
  - standalone selector/MAC target using explicit sparse indices and vector-valid bits;
  - normal-conv and point-wise-conv schedules that skip all-zero sparse weight vectors and report active/skip counters.
- Future top-level integration should connect compressed weight/index streams through the activation buffer path rather than only using generated vector-valid masks.

## 6. Depth-Wise Conv Reuse From Fig. 4

Plain-language view:

Depth-wise convolution cannot share one activation across many output channels. e-G2C instead squeezes more use out of the same channel by mapping nearby rows to several MAC lanes at once.

Paper terms:
- CIR: column-wise intra-channel reuse.
- D-RIR: deeper row-wise intra-channel reuse.

Architecture-level plan:
- First implement a simple depth-wise convolution loop.
- Current RTL adds an output-equivalent analytical counter model for simple/CIR/D-RIR trends.
- A true reuse-mode scheduler that assigns related output positions to lanes in parallel remains TODO.
- Verify with small tensors that any future optimized schedule matches the simple golden output.

## 7. Threshold Adaptation From Fig. 6

Plain-language view:

The detector threshold is not fixed forever. The chip keeps a histogram of detector outputs, finds the least-populated interval in the sensitive range, and puts the threshold in the middle of that quiet interval.

Paper flow:
1. Use comparators to build a histogram over T days.
2. Use argmin to find the least-occurrence interval.
3. Update the threshold and reset histogram counters.

Architecture-level RTL plan:
- `eg2c_threshold_cmp.v`: compares detector output with the current threshold.
- `eg2c_histogram.v`: increments interval counters.
- `eg2c_argmin.v`: finds the smallest counter.
- `eg2c_adapt_engine.v`: owns threshold registers and update control.

## 8. Known Missing Details

The VLSI paper is short. It does not fully specify:
- Exact input tensor height/width used by the hardware.
- Padding, stride, and activation function choices for every layer.
- Quantization scale/zero-point details.
- Original trained weights and datasets.
- Full 32-bit instruction encoding.
- Exact sparse weight packing format.
- Exact cycle schedule for every dataflow.

For architecture-level reproduction, these will be treated as implementation assumptions and documented when chosen.

## 9. Evidence And Assumption Register

Use this table whenever the implementation needs a detail that is not explicit in the paper. A row marked "assumption" must be mirrored in the relevant RTL comments or Python generator comments when it becomes executable behavior.

| Topic | Paper fact | Implementation assumption | Evidence / status |
|---|---|---|---|
| Code directory layout | Paper does not discuss repository layout | RTL, testbenches, scripts, and simulation runner live at repo root; e-G2C documents and extracted paper assets live under `e-G2C/` | User requested e-G2C docs under `e-G2C/`; code path chosen for this repository |
| Activation numeric format | Fig. 8 says 8-bit activation | First dense baseline uses signed 8-bit two's-complement activations | Paper fact for width; signedness chosen for simulation |
| Weight numeric format | Fig. 2/8 mention 4-bit power-of-2 and 8-bit int weights | First dense baseline uses signed 8-bit weights; 4-bit packed mode is delayed until sparse/weight-format phase | Paper fact for available formats; staged implementation choice |
| Output numeric format | Fig. 8 says 8-/16-bit output | First dense baseline writes signed saturated 8-bit activations | Paper permits 8-bit output; 16-bit can be added later |
| Accumulator width | Paper does not give internal accumulator width | Use signed 32-bit accumulator in first baseline | Conservative simulation choice |
| Tensor layout | Paper figures show tensor blocks but no memory flattening order | Use NHWC activation layout and `kh, kw, cin, cout` normal-conv weight layout for generated tests | Must be frozen before Phase 3 |
| Padding and stride | Fig. 5 lists kernel shapes but not padding/stride | Default convolution tests use stride 1 and explicit zero padding; exact target stored in `target.json` | Must be recorded per test |
| Activation function | Paper does not list nonlinearities per layer in the VLSI summary | First dense tests are linear plus output saturation; ReLU or other activation is a later parameter | Avoids inventing model behavior too early |
| Quantization scale / zero point | Not specified | No scale/zero-point in first dense baseline; direct accumulator saturation | Keeps arithmetic verifiable without trained model export |
| 32-bit instruction encoding | Paper says 32-bit instructions from Instruction SRAM | Define a simulation encoding; use context memory if shapes do not fit cleanly in 32 bits | Must be documented before Phase 4 |
| Sparse vector packing | Fig. 3 explains vector-wise sparsity behavior, not exact bit packing | Standalone sparse MAC uses vector-major unsigned 16-bit indices, signed 8-bit sparse weights, and one `vector_valid` bit per sparse vector. Normal/PW conv schedules now use generated `vector_valid` masks for all-zero sparse weight vectors: normal conv groups one kernel row per output channel, PW groups three input-channel weights per output channel. Full top-level compressed index/weight streaming remains future work. | Project-local Phase 6 model |
| DW reuse exact schedule | Fig. 4 illustrates CIR and D-RIR but not a full cycle table | Implement output-equivalent schedules and report simulated utilization trends, not exact ASIC cycle claims | Phase 7 assumption |
| Adaptation intervals | Fig. 6 shows intervals and T-day histogram, but not numeric boundaries | First test uses generated interval boundaries, signed 8-bit score/threshold, 16-bit counters, and integer midpoint truncation | Phase 8 assumption |
| External sources | References are listed but not yet fetched | If used, record URL, access date, and whether source is primary or secondary before changing implementation assumptions | Required for future research |

## 10. Local Figure Lookup

Extracted support files:

| Item | Local path | Notes |
|---|---|---|
| Searchable paper text | `e-G2C/extracted/paper_text.txt` | Generated with `pdftotext -layout`; committed |
| Full page 1 image | `e-G2C/extracted/pages/page_01.png` | Generated locally with `pdftoppm`; ignored by Git |
| Full page 2 image | `e-G2C/extracted/pages/page_02.png` | Generated locally with `pdftoppm`; ignored by Git |

Figure locations in the rendered page images:

| Figure | Page image | Implementation relevance |
|---|---|---|
| Fig. 1 pipeline | `page_01.png` | Detector branch into coarse/precise conversion |
| Fig. 2 architecture | `page_02.png` | Memory blocks, MAC lanes, controller, adaptation engine |
| Fig. 3 vector-wise sparsity | `page_02.png` | Sparse normal/PW conv data path |
| Fig. 4 DW reuse | `page_01.png` | CIR and D-RIR scheduling |
| Fig. 5 model structures | `page_01.png` | Detector/coarse/precise layer lists |
| Fig. 6 threshold adaptation | `page_02.png` | Histogram, argmin, threshold update |
| Fig. 7 chip micrograph | `page_02.png` | Context only; no architecture-level RTL target |
| Fig. 8 measurements | `page_02.png` | Context only; no ASIC metric claim |

## 11. External Research Log

No external source has been used yet.

When external material is used, add entries in this format:

```text
- YYYY-MM-DD: <title>, <URL>, <primary/secondary>, used for <which missing detail>.
```
