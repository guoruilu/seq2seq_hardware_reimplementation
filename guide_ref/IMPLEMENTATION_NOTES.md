# IMPLEMENTATION NOTES — 从"骨架"到"完整复现 + Vivado 上板"的路线图

> 本文用 6 个 Step 描述把现在的"单层 conv1d 骨架"扩成论文完整 CS-DAE 网络 + 上板的具体做法。每个 Step 都按"目标 → 改哪些文件 → 怎么验证"三段写。
>
> 写给 Verilog 初学者：每个新概念**先打比方再讲术语**；如有公式，先给一句"人话翻译"。

---

## IP 核清单（论文里依赖的 IP / 工程内对应文件）

| IP 名称                  | 论文出处         | 工程文件                            | 行为级实现 | 综合上板时的处理 |
|--------------------------|------------------|-------------------------------------|------------|-----------------|
| DSP48E1 (multiplier+MAC) | Fig.11 / Fig.12  | `csdae_conv1d.v`                    | YES (Verilog `*` + `(* use_dsp = "yes" *)`) | Vivado 自动推断 DSP，或显式换 Multiplier IP |
| Block Memory Generator   | Fig.7 "RAM"      | `csdae_ldm.v`、`csdae_*_mem.v` (4 块) | YES (reg 阵列 + ASYNC 读) | 改回 SYNC 读后 Vivado 推 BRAM；上层流水加 1 拍 |
| AXI4-Lite Slave          | Fig.7 cmd reg    | `csdae_axi_lite_slave_stub.v`        | NO（仅接口 stub）  | 拉 Xilinx 自动生成的 AXI Slave 替换；接口语义已注释清楚 |
| AXI4-Stream / AXI DMA    | Fig.7 / Sec.III-A | `csdae_axi_dma_stub.v`               | NO（仅接口 stub）  | 拉 Xilinx "AXI DMA" IP 替换；与 stub 端口语义对齐 |
| MMCM / PLL (167 MHz 时钟)| Sec. III-E       | 工程外（约束在 .xdc 里）              | NO（属于 SoC 时钟设计） | Vivado IP Integrator 用 `clk_wiz` IP |

> 凡是新增 RTL 模块涉及 IP 时，文件头要按 `CLAUDE.md` 规则 7 标注。

---

## 当前工程已实现的部分（基线）

- 第 1 层 1D 卷积（Ch_in=1, Ch_out=12, K=7, N=1024，same-padding，stride=1）的"骨架数据通路"；
- 量化 (8-bit / 8-bit / 32-bit acc / `>>>25`) + ReLU；
- 4 个 PE 并行不同输出通道；
- iverilog 仿真单层数值与 Python golden 完全一致。

下面 6 个 Step 把它扩成论文完整 13 层 + 上 PYNQ-Z2。

---

## Step 1 — 支持 Ch_in > 1（多通道累加）— ✅ 已完成

**问题来源**：第 1 层 Ch_in=1 已经过；但 encoder/decoder 后续层 Ch_in=12/24，需要把多个输入通道的 partial-sum 累加起来才能得到一个输出像素。

**人话**：现在每个输出像素 `out[co][n] = bias + 1 个输入通道贡献`。多通道时变成 `out[co][n] = bias + Σ_{ci=0..Ch_in-1} (这个通道的卷积 partial)`。

### 改动

1. **`csdae_schedule_ctrl.v`**：
   - 加外层循环 `for ci in 0..Ch_in-1`。
   - 第一个 ci (=0): `acc_clr=1`（把 acc 预置为 bias）。
   - 中间 ci (>0 且 <Ch_in-1): `acc_clr=0`，只 `acc_en`。
   - 最后一个 ci (=Ch_in-1): `flush=1` 触发量化 + 写回 LDM。
   - 也就是说："flush 在所有 ci 都累加完之后才拉一次"，而不是当前每拍都拉。

2. **`csdae_weight_mem.v`**: 地址按 `(co * Ch_in + ci) * K + k` 编址；其实 `csdae_defines.vh` 里 `CSDAE_WMEM_DEPTH` 已经按 `MAX_CHIN * MAX_CHOUT * K` 算过了，无需改 RTL。
3. **`csdae_feature_mem.v`**: 用 `addr = ci * MAX_FEAT + n` 多通道访问，已经支持，无需改。

### 验证

更新 `scripts/golden_conv1d.py`：把 `CH_IN=1` 改成 `CH_IN=12`（模拟第 2 层），重新生成 golden；testbench 也相应改。期望 `0/4096 mismatches`。

> ⚠️ 注意：FAQR 当前结构假设 1 partial 1 输出。改 ci 维循环时，FAQR 的 `acc_clr / acc_en / flush` 时序要小心，不要在中间 ci 时让 flush 误触。波形里盯 `faqr.acc, faqr.flush` 两个信号即可。

---

## Step 2 — 接入 Pixel-Unshuffle / Pixel-Shuffle — ✅ 完成（含 ctx 触发，Step 4 把 schedule_ctrl 集成补齐）

**问题来源**：encoder 在 conv 之后做 Pixel-Unshuffle（C↑×2, N↓×2），decoder 用 Pixel-Shuffle（C↓×2, N↑×2）。这两个模块已经写好（`csdae_pixel_unshuffle.v` / `csdae_pixel_shuffle.v`），只是还没有被 schedule_ctrl 调用。

**人话**：这两个模块只做"数据搬家 + 重新编号地址"，不动数。

### 改动

1. **`csdae_schedule_ctrl.v`**：加 `S_PSHUF`、`S_PUSHUF` 状态。状态进入时拉 `pshuf.start=1`，等 `pshuf.done=1` 后转回 `S_BATCH_DONE`。
2. **`csdae_top.v`**：例化 `csdae_pixel_unshuffle` 和 `csdae_pixel_shuffle` 各一份，把它们的读口接 `feature_mem` 读口，写口接 `feature_mem` 写口（注意需要 mux：当 schedule 在 conv 阶段时，feature_mem 写口接 PE 的输出回写；在 pshuf 阶段时接 pshuf 模块）。
3. **`csdae_defines.vh`**：`CSDAE_PSHUF_R` 默认 2，按层可改（论文每层都用 R=2）。

### 验证

- 单测：写一个 `tb_csdae_pshuf.v`，构造 (C=2, N=8) 的特征，跑一遍 unshuffle → 期望 (C=4, N=4)；再跑 shuffle 还原回 (C=2, N=8)；位级比对。

---

## Step 3 — 多层串跑（Context Memory）— ✅ 已完成

**问题来源**：论文整网络 = 3 个 conv + 6 个 encoder + 6 个 decoder + 6 个 CS。每层参数（Ch_in, Ch_out, N, op_type, weight 起始地址, bias 起始地址 ...）不一样。

**人话**：给每一层做一张"配方卡"，控制器逐张读、逐张执行。

### 已落地的改动

1. **`csdae_ctx_mem.v`**：80-bit×NUM_LAYERS=19 async-read 小 RAM，存每层"配方"。
2. **`csdae_defines.vh`**：定义 `CSDAE_CTX_W=80` 与 9 个字段位段宏
   `CSDAE_CTX_NIN/CHIN/CHOUT/OP/SRCB/DSTB/WBASE/BBASE/RELU(x)`。
3. **`csdae_schedule_ctrl.v`**：
   - 加 `S_CTX_LOAD` 状态，从 ctx 解字段锁存到 `N_in_r/Ch_in_r/...` 内部寄存器；
   - 加 `layer_idx` 外循环；
   - `S_DUMP_LDM` 末尾判断：本层 batch 全完 ⇒ 若还有层就 `layer_idx++ → S_CTX_LOAD`，
     否则 `S_DONE`；
   - fmem/wmem/bmem 寻址公式全部加 `src_base_r / wbase_r / bbase_r` 偏移。
4. **`csdae_top.v`**：例化 ctx_mem，加 `num_layers + cmem_we_ext/cmem_waddr_ext/cmem_wdata_ext`
   端口；移除原 `N_in/Ch_in/Ch_out/output_base` 端口（这些都从 ctx 来）。
5. **`scripts/golden_multilayer.py`**：接收 `LAYERS=[{chin,chout,n,relu},...]` 列表，
   生成 input/weights/bias/golden/ctx 五份 hex 文件 + `multilayer_dump.txt`。每层 base 偏移
   (src/dst/wbase/bbase) 自动连续排布。
6. **`tb/tb_csdae_chain.v`**：默认 2 层 (1→4 → 4→4, N=1024)；灌好 mem 后
   `start=1, num_layers=2`，等 `done`，从 fmem dst1 区读出比对 golden。

### 验证（已跑通）

- 单层 ctx 驱动回归：`./sim/run_sim.sh chin=1/2/4/12`，全 0/12288 PASS。
- 2 层 chain：`./sim/run_sim.sh chain`，0/4096 PASS。
- 暂未跑 3 层 / PyTorch 浮点参考；有需要可在 golden_multilayer.py 末尾加层数即可。

---

## Step 4 — ctx 触发 pshuf + Compact Shortcut（CS）+ Concat

### 第 1 阶段（已完成）— ctx 触发 pshuf

- `csdae_schedule_ctrl.v` 加 `S_PSHUF` / `S_PSHUF_WAIT` 状态：S_CTX_LOAD 后根据 op_type
  分支（CONV1D=2 → S_BATCH_INIT；PSHUF=3 / PUSHUF=4 → S_PSHUF）。
- ctrl 驱动 `ctrl_pshuf_op/start/N/C/src_base/dst_base/active`，等 `pshuf_done` 后跳 next layer。
- top 把 ctrl_pshuf_* 与 tb 直控 pshuf 信号 mux（`ctrl_pshuf_active=1` 时 ctrl 优先）。
- pshuf 模块默认 stride 改 `FMEM_CH_STRIDE`，schedule_ctrl 调 pshuf 时 base 加 `PAD`，
  使 conv 输出布局与 pshuf 寻址完全对齐（详见 BUGFIX #007）。
- `golden_multilayer.py` 支持 `"op": "conv1d"|"pushuf"|"pshuf"`；3 层 chain
  (conv 1→4 → pushuf 4→8 → conv 8→4) 0/256 PASS。

### 第 2 阶段（已完成）— CS + Concat

**已落地的改动**：

1. **CTX 扩 88-bit**：`csdae_defines.vh` 加 `CSDAE_CTX_SRCB_B(x) = x[87:73]` (15 bit)
   存放 concat 的第二个源基址。其它字段位段不变。
2. **`csdae_concat.v`**：channel-wise 串接搬运模块，async-read + 同拍写。
   接口：`Ch_a / Ch_b / N / src_a_base / src_b_base / dst_base`，`done` 拉一拍。
   每拍读 1 写 1，总 `(Ch_a+Ch_b)*N` 拍。stride = `FMEM_CH_STRIDE`，base 由调用方 +PAD。
3. **CS 用现有 conv1d 路径**：硬件不动。`golden_multilayer.py` 加 op="cs"：
   生成 `(chout, chin, K=7)` 权重但只有 `w[...,0]` 非零，其他位 0。这样硬件计算
   `Σ sr[i]*wmem[i]` 等价 `out[n] = in[n]*w` (1×1 conv 数学)。CS 层 ctx 仍写 `OP_CONV1D`。
4. **schedule_ctrl 加 `S_CONCAT/S_CONCAT_WAIT`**：S_CTX_LOAD 后 op=OP_CONCAT 分支进入；
   驱动 `ctrl_concat_*` (active/start/N/Ca/Cb/src_a_base/src_b_base/dst_base)，
   等 `ctrl_concat_done` 后跳下一层。
5. **top 加 4 路 fmem mux**：concat > pshuf > dump > 后门 ext。
6. **`golden_multilayer.py` 加 op="concat"**：layer dict 用 `src_b_layer` 字段索引较早层；
   脚本维护 `layer_outputs[]` 列表，concat 时 `cur = concatenate([cur, layer_outputs[idx]], axis=0)`。
   ctx 写 src_b_base = `layer_meta[src_b_layer]["dst_base"]`。

**验证（已跑通）**：

- `tb_csdae_chain.v` 默认 4 层 chain：conv (1→4, N=64) → CS (4→4) → concat (L1+L0 → 8ch) →
  conv (8→4)。`./sim/run_sim.sh chain` 输出 0/256 PASS。
- 全套回归（pshuf 单测 + conv chin=1/2/4/12 + 多层 chain）全部 PASS。

**未做（不在本工程当前阶段范围）**：

- 完整 13 层 CS-DAE 网络的端到端测试（需要 PyTorch 浮点参考训练 + 量化导出权重）。
- pshuf+CS 混跑（encoder 用 pushuf 后立刻 CS 压缩通道）。理论上数据通路 + ctx 调度都已 ready，
  写一个新 LAYERS 即可，不需要 RTL 改动。

### 第 2 阶段（旧版规划，保留作 reference）— CS + Concat

**问题来源**：论文的"亮点" — encoder 的输出**经过 CS 层压缩通道后**送到 decoder，而不是简单 add 残差。CS 用一个 transposed-conv (1×1) 改变通道数。

**人话**：encoder 中间结果不仅向下游 decoder 传，还会经过一条"小流水"先做通道压缩。

### 改动（待做）

1. **`csdae_conv1d.v`**：把 K=7 改成参数化（`parameter K = `CSDAE_K`）的同时支持 K=1
   退化（sr 直传 + 1 个乘法）。或者新建 `csdae_conv1x1.v` 单独走 CS 路径。
2. **`csdae_schedule_ctrl.v`**：op_type=`CSDAE_OP_CS=6` → 走 CS 通路。简化做法：复用 conv 通路
   把 K_eff 临时切到 1，权重布局调整。
3. **`csdae_concat.v`**：channel-wise concatenation，纯地址映射搬运。
   ctx 加 `CSDAE_OP_CONCAT=5` 触发，配两个 src_base（A/B 两段）+ 一个 dst_base。
4. **golden_multilayer.py**：加 op_concat / op_cs 模拟。
5. **tb_csdae_chain.v**：4~5 层链 `conv → pushuf → CS → concat → conv`。

### 验证

- 跑 1 个 encoder + 1 个 CS + 1 个 decoder 的微缩网络，验证 CS 输出在 decoder 入口的位置和数值正确。

---

## Step 4.5 — 扩到论文 13 层 ✅ 完成（方案 D + A）

**最终结论**：方案 D（N=128 微缩）+ 方案 A（fmem 扩到 198 KB + ctx 加宽）联合完成，
全部跑通 0/128 + 0/512 mismatches。下面保留评估细节与方案表，作为未来回看参考。

### 方案 D 落地

- 11 层 U-Net at N=128：conv1d(1→2) → 5×cs(2→2) → pushuf(2→4) → cs(4→2) → pshuf(2→1)
  → concat(src_b=L5) → cs(3→1)。fmem 占满 24×1030=24720。
- `scripts/chain_d_layers.json` + `tb/tb_csdae_chain_d.v` + `sim/run_sim.sh chain_d`。
- 副作用：`golden_multilayer.py` 加 per-layer `b_range/scale` 覆盖。原 CS 默认 scale ×7
  在长链中会饱和到 ±127；测试要传小 scale (≈10000~50000) 才能维持 dynamic range。

### 方案 A 落地

defines 改动（不再是"1 行"了，结构性更改）：

| 变量 | 原值 | 新值 | 原因 |
|------|------|------|------|
| `MAX_FMEM_CHANNELS` | (无) = `MAX_CHIN`=24 | **192** (脱钩 MAX_CHIN) | fmem 槽位独立 |
| `FMEM_DEPTH` | 24 × 1030 = 24720 | **192 × 1030 = 197760** | 198 KB |
| `WMEM_DEPTH` | `MAX_CHIN×MAX_CHOUT×K` = 4032 | **`NUM_LAYERS×MAX_CHIN×MAX_CHOUT×K` = 76608** | 多层串接 |
| `BMEM_DEPTH` | `MAX_CHOUT×4` = 96 | **`NUM_LAYERS×MAX_CHOUT` = 456** | 多层串接 |
| `CTX_W` | 88 | **112** (28 hex digit) | src/dst/sb_b 18bit, wb 17bit, bb 9bit |

跟改：
- `csdae_bias_mem.v`：`MAX_CO` 参数改为 `DEPTH`，深度跟 `BMEM_DEPTH`。
- `csdae_top.v` / `csdae_schedule_ctrl.v` / `tb_csdae_*.v`：`BAW = $clog2(BMEM_DEPTH)`
  替代旧的 `$clog2(MAX_CHOUT)`。
- CTX 宏全部改位段（见 `csdae_defines.vh`）。
- `tb_csdae_top.v::make_ctx` 与 `scripts/golden_multilayer.py::make_ctx` 同步：
  Verilog 输入位宽 18/18/17/9/18，hex 输出 28 位。
- `scripts/chain_a_layers.json` 13 层（conv → 3×(pushuf+cs) 编码器 → 3×(pshuf+concat+cs)
  解码器，含 src_b_layer=2,4 的两条 CS shortcut）。
- `tb/tb_csdae_chain_a.v` + `sim/run_sim.sh chain_a`。

跑出来：fmem 用 187 KB / 198 KB，运行 171K cycles，bit-level 0/512 PASS。

### 评估细节（保留备查）

**结论**：当前 fmem 装不下完整 13 层（24 通道层就占满整个 fmem）。需要扩容或改布局。

### 评估细节

论文完整网络 13 层，关键约束：

```
输入 1 × 1024
↓ conv             (1 → 12, N=1024)              占 12 × 1030 = 12 KB
↓ E1 encoder       (24 → 24, N=512)              占 24 × 1030 = 24 KB ← 单层填满 fmem
↓ E2..E6 encoder   (24 → 24, N=256/128/64/32/16) 每层 24 × 1030 = 24 KB
↓ + 6 条 CS        encoder 输出全部要保留供 decoder concat
↓ 6 个 decoder     恢复 N → 1024
↓ 末层 conv        (12 → 1)
```

**当前 fmem**：`FMEM_DEPTH = MAX_CHIN × FMEM_CH_STRIDE = 24 × 1030 = 24,720` 字节。

**需要**（保留所有 encoder 输出 + decoder workspace）：
- 6 个 encoder 输出 × 24 × 1030 = ~145 KB
- decoder 工作区 + 末层 ~20 KB
- **总计 ~165 KB**

### 待选方案表

| # | 方案 | 改动量 | fmem 用量 | 仿真速度 | 备注 |
|---|------|--------|----------|---------|------|
| A | `MAX_CHIN=168` | 1 行 defines | 173 KB | 慢 (大) | 最简单粗暴 |
| B | per-layer 变长 stride（ctx 加字段） | 中等 RTL | ~30 KB | 快 | 工程上最优 |
| C | ctx 手写 ping-pong 布局 | 仅写 ctx | 24 KB | 快 | CS 依赖让复用空间小 |
| D | 缩小测试 (N=128 → 13 层) | 调 LAYERS 即可 | < 24 KB | 快 | 验证调度逻辑足够 |

### 推荐路径

1. 先做方案 D：把论文 13 层等比缩小到 N=128 跑通，证明硬件 + ctx 调度逻辑能 hold 完整网络。
2. 真要跑论文实际尺寸（N=1024）时再做方案 A 或 B。
3. 方案 C 对 CS 依赖密的网络风险高，不优先。

### 阻塞 P3

P3（PyTorch 训练 → 量化 → 灌硬件）依赖 fmem 容量解决，否则无处放训练好的真实层间数据。
方案 D 不依赖训练，可以先做。

---

## Step 5 — AXI4-Lite + AXI4-DMA 接口（替换"后门"）

**问题来源**：当前 `csdae_top.v` 的接口是仿真后门；要上板必须按 Vivado 的 AXI 接口规范。

**人话**：`AXI4-Lite` = "命令信道"（PS 写一个寄存器告诉 PL"开始算第 5 层"）；`AXI4-DMA` = "数据搬运通道"（PS 把权重、输入 ECG 直接 push 进 PL，跑完再 pull 出来）。

### 改动（建议直接用 Xilinx IP，不要自己手写 AXI Slave）

1. **`csdae_axi_lite_slave.v`** (新)：暴露这些 32-bit 寄存器
   ```
   0x00 control       [bit0 start, bit1 reset]
   0x04 status        [bit0 done, bit1 busy]
   0x08 layer_count
   0x0C ctx_base_addr
   0x10 weight_base_addr
   0x14 input_base_addr
   0x18 output_base_addr
   ```
2. **AXI DMA 替代后门**：在 IP Integrator 里拉 `axi_dma_0` IP，把它的 M_AXIS 接到 `csdae_top.v` 的 `feat_in_*` 流入端口；S_AXIS 接 `feat_out_*` 流出端口。
3. **`csdae_top.v`**：把 `*_we_ext` 系列后门换成 AXI-Stream 风格 (TVALID/TREADY/TDATA)。

### 验证

- Vivado 行为级仿真（用 `axi_vip` IP master 模拟 PS 行为）。
- 上板：PYNQ Python 写个 jupyter notebook，用 `pynq.lib.dma` 把权重、ECG 推到 PL，跑完读回，对比 PC 端 PyTorch 量化模型输出。

---

## Step 6 — Vivado 综合 / 实现 / 上板

### 替换 BRAM IP

当前 4 块 RAM 都是 reg-array (ASYNC 读)。综合到 BRAM 时：
- 在 `csdae_*_mem.v` 中把 `assign rdata = mem[raddr]` 改回 `always @(posedge clk) if (re) rdata <= mem[raddr]`；
- **同时** 在 `csdae_schedule_ctrl.v` 中所有 `*_re/raddr → rdata 消费` 流水各加 1 拍。
- 或者更省事：用 Vivado 的 Block Memory Generator IP，配 `Read Latency = 1`，逻辑改动同上。

### 替换 DSP

`csdae_conv1d.v` 里 `mul[i] <= sr[i]*w_flat[i]`，Vivado 默认会推 DSP48。要强制：在乘法前加属性 `(* use_dsp = "yes" *)`。论文里 1 D Conv 用 7 个 DSP，与本工程一致。

### 综合期望（论文 Table IX 里）

| 资源    | 论文 PYNQ-Z2 占用 |
|---------|---------------------|
| BRAM    | ≈ 37.50%            |
| DSP     | ≈ 16.82%            |
| 时钟    | 167 MHz             |
| 功耗    | 1.65 W              |

我们这套实现因为 PE 数和 RAM 容量参数化默认偏宽，预计第一次综合会超出。**用 `csdae_defines.vh` 把 `CSDAE_MAX_*` 调到论文实际尺寸即可**。

### 板上实测建议

- 先不带 ECG，给 PL 灌 fixed pattern (e.g. 全 1 输入 + 单位脉冲权重)，对比期望脉冲响应。
- 然后用 NSTDB 数据集（论文用同一个），跑 PRD / SNRimp 与论文 Table VII / VIII 的"Ours"行对比；当前文献给出 PRD ≈ 46.30%、SNR_imp ≈ 10.50。

---

## 注意事项 / "坑"清单（按踩坑频率排序）

1. **同步读 vs 异步读 时序错位 1 拍**：当前所有 mem 都是 ASYNC；切回 sync 时记得 schedule_ctrl 各处再加 1 拍 pipeline。详见 `BUGFIX.md #001`。
2. **卷积权重逆序写**：硬件 sr[0]=最新输入导致硬件计算 cross-correlation 而非 convolution。Python golden 已经按"逆序写 weights.hex"处理，这一点要在改动 `csdae_conv1d.v` shift register 方向时**记得同步改 golden**。详见 `BUGFIX.md #002`。
3. **STARTUP_LAT 必须等于"输入流水阶段数 + (K-1) + LATENCY"**：改 K 或加输入流水时记得同步改这个常量。详见 `BUGFIX.md #003`。
4. **iverilog `always @*` + 模块级 integer 循环计数会零时间死循环**：本工程 `for` 都在 `always @(posedge clk)` 里安全使用；新增组合逻辑循环时按 generate-for 写。
5. **不要忘记给 PE LDM 容量加足**：`Ch_out > NUM_PE` 时同一块 LDM 在多个 batch 之间被覆盖，testbench 当前只能看最后一批。完整解决方案见 Step 1 末尾。
