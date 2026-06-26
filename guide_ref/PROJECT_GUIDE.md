# CS-DAE Verilog 工程导览（小白友好版）

> 适用读者：写过 SPI、UART、简单状态机的 Verilog 初级使用者，**没**写过 CNN 加速器、量化或 AXI。
>
> 阅读建议：**先看第 1 节"一句话总览"和第 2 节"形象比喻"**，再看第 3 节模块清单，然后挑一条数据通路（第 5 节）跟着箭头走一遍，就能上手了。

---

## 1. 一句话总览

这个工程是论文 **2025 TCASI - VLSI Architecture Design for Compact Shortcut Denoising Autoencoder Neural Network of ECG Signal** 的硬件实现：

> 一颗有 **4 个并行 PE（处理单元）** 的小型 CNN 加速器，用来跑一维（1D）卷积神经网络 CS-DAE 给心电图（ECG）信号去噪。

**当前阶段**：Step 1~4 全部完成 — 单层多通道 conv1d、Pixel-(Un)Shuffle、ctx 驱动多层
chain (conv/pshuf/CS/concat) 全部跑通。iverilog 仿真：单层 chin=1/2/4/12 全 `0/12288`；
4 层 chain conv→CS→concat→conv `0/256`；3 层 conv→unshuf→conv `0/256`；pshuf round-trip bit-level 对齐。

**核心要解决的问题**：1D 卷积每个输出像素都要做 K=7 次乘加；CS-DAE 整个网络有 ~8.32M MACs。CPU 跑慢，所以用专用电路：
- 把 7 个乘法器并行做卷积（`csdae_conv1d.v`，论文 Fig.11）；
- 4 个 PE 同时做不同的输出通道（论文 Fig.7-8）；
- 量化把 32-bit 浮点压成 8-bit 整数，省内存省功耗。

---

## 2. 形象比喻：把芯片想成一个"流水线饺子工厂"

| 现实里 | 工程里对应 |
|--------|-----------|
| 工厂总指挥（看菜单分配活） | `csdae_schedule_ctrl`（控制器/状态机） |
| 食材仓库（采购回来的面、馅、油） | `csdae_feature_mem`（输入/中间特征 RAM） |
| 配方柜（每道菜怎么调味） | `csdae_weight_mem`（权重 RAM）+ `csdae_bias_mem`（偏置/量化参数） |
| 4 个工位（同时切 4 种饺子皮） | `csdae_pe_array` 里的 4 个 `csdae_pe` |
| 每个工位上的小工作台 | `csdae_ldm`（PE 内的本地 RAM） |
| 工位上的料理工具（刀、秤、压面机） | `csdae_conv1d`（一维卷积）+ `csdae_faqr`（量化+ReLU） |
| 拉面师傅把面"对折再展开"（变粗变短/变细变长） | `csdae_pixel_unshuffle` / `csdae_pixel_shuffle` |
| 与外界（订单、外送）的对接窗口 | `axi_*` stub（暂未实现） |
| 整个工厂的门牌房间 | `csdae_top.v`（顶层） |

**网络推理 = 一道道菜（一层 Conv → 池化 → ReLU → 拉面 → 又一层 Conv）按顺序做**。每道菜按"配方"（K, N, Ch_in, Ch_out, stride 等）执行。

---

## 3. 模块清单（每个一句话职责 + 接口看哪里）

> 路径都在 `rtl/` 下。位宽默认值在 `csdae_defines.vh`。

### 3.1 `csdae_defines.vh` — "全局参数表"
不是模块，是宏定义文件。所有 RTL 用 `` `include "csdae_defines.vh" `` 引入。
**改这里就能改全工程**：位宽、PE 数、最大网络规模、操作码编码。论文里出现的所有数字（K=7、SHIFT=25、Ch_out=24、N=1024 等）都来自这里。

### 3.2 `csdae_ldm.v` — Local Data Memory（本地数据 RAM）
- **是什么**：一块小 BRAM（默认 1024×8-bit），放在每个 PE 内部，存当前层的输入或输出特征。
- **类比**：就像工位上的小冰箱，不用每次去外面大仓库（`feature_mem`）取料。
- **接口**：写口 `we / waddr / wdata` + 读口 `re / raddr / rdata`。当前为 **ASYNC 读** (LUTRAM 风格)，到 Vivado 替换 BRAM 时改回同步读，注意上层流水要相应再加 1 拍。

### 3.3 `csdae_conv1d.v` — 一维卷积引擎（论文 Fig.11）
- **是什么**：把 7 个连续输入和 7 个权重做"逐位相乘再求和"，每拍出一个 partial-sum。
- **解决什么**：1D 卷积公式 `out[n] = Σ_{k=0..6} in[n+k]·w[k]`。如果一拍只乘一次要 7 拍才算 1 个输出；这里 7 个乘法器并行 + 4 级流水加法树，每拍 1 输出。
- **关键内部结构**：
  1. **shift register**：输入 1 拍 1 个，沿 `sr[0]→sr[6]` 流动。
  2. **7 个并行乘法器** (Vivado 综合时变 DSP48E1)。
  3. **4 级流水加法树** (论文："2 个 adder + 4-level pipeline")。
- **总延迟**：`LATENCY = 1(sr) + 1(mul) + 4(adder) + 1(out_reg) = 7` 拍。
- **注意 / 踩过坑**：
  - 由于 sr 的填法 (sr[0]=最新, sr[6]=最旧)，硬件实际算的是 `Σ in[t-i]·w[i]`，等同于把权重逆序后再做"普通卷积"。所以 Python golden 把权重排到 wmem 时会**逆序**写入。详见 `BUGFIX.md #002`。

### 3.4 `csdae_faqr.v` — Feature Accumulation, Quantization & ReLU（论文 Fig.13）
- **是什么**：3 件事打包：
  - **F**: 累加多通道的 partial-sum 到 32-bit accumulator。
  - **Q**: 量化 — 把 32-bit acc 通过 `(acc * scale_q25) >>> 25` 压回 8-bit。
  - **R**: ReLU — 负数砍成 0。
- **解决什么**：神经网络训练用浮点；硬件用 8-bit 整数算更省。论文式 (5)–(14) 描述了这套量化数学。本模块是这套数学的硬件版。
- **多通道累加（Step 1 升级）**：内部带一块 `partial_mem`（深度 = MAX_FEAT，宽 = 32-bit），
  存"每个输出位置 n 的中间累加值"。外部 schedule_ctrl 给出三个信号配合：
  - `mode_first` = 1 时（ci=0），`partial_mem[n] <= bias + partial`（用 bias 初始化）；
  - 中间 ci（`mode_first=0 && mode_last=0`），`partial_mem[n] <= partial_mem[n] + partial`；
  - `mode_last` = 1 时（ci=Ch_in-1），不写回，直接量化 + ReLU 输出到 LDM。
- **Ch_in=1 退化**：`mode_first=mode_last=1`，等价于"bias + 1 个 partial → 量化"。
- **关键时序**：每拍 1 partial，新累加值组合算（`new_acc = pre_acc + partial`），下一拍量化输出寄存器化（faqr.out_valid 比 acc_en 晚 1 拍）。

### 3.5 `csdae_pe.v` — Processing Element
- **是什么**：1 个 PE = 1× `csdae_conv1d` + 1× `csdae_faqr` + 1× `csdae_ldm`。
- **形象**：1 个工位。所有工位结构一样，差别在于它分到哪个输出通道、当前的权重和偏置是什么。

### 3.6 `csdae_pe_array.v` — PE Array
- **是什么**：4 个 `csdae_pe` 的并行阵列（论文 Fig.7）。
- **共享**：所有 PE 都收到同样的输入像素流和控制信号；
- **独立**：4 套权重 / bias / scale，4 块 LDM。
- **就是为什么并行能加速**：4 个不同的输出通道 (co) 一起算。Ch_out=12 用 3 批 (batch) 跑完。

### 3.7 `csdae_pixel_unshuffle.v` / `csdae_pixel_shuffle.v`
- **是什么**：纯地址变换的搬运模块，不算数。
- **Pixel-Unshuffle**（encoder 用）：`(C, N) → (C·R, N/R)`。把"长队伍"折叠成"R 排短队伍"。
- **Pixel-Shuffle**（decoder 用）：上面这个的反操作。
- **为什么神经网络要做这个**：传统 CNN 用 maxpool/upsample 改变特征长度，但会丢信息；pixel-shuffle 是无损重排，论文用这两个在 encoder/decoder 里改长宽不丢精度。

### 3.8 `csdae_feature_mem.v` / `csdae_weight_mem.v` / `csdae_bias_mem.v`
- 大小不一样的几块 RAM，分别存特征 / 权重 / 量化参数（bias_q + scale_q25 + zero_point + relu_en）。
- **当前都是 ASYNC 读** — 仿真时序最简单。综合到 BRAM 改同步读时，需要在 `csdae_schedule_ctrl.v` 里把"读地址 → 消费"流水再加 1 拍。

### 3.9 `csdae_schedule_ctrl.v` — 总调度（论文 Fig.10）
状态机翻译论文里的执行流程。Step 3 后支持任意层数的 conv1d chain（参数全部从 ctx 读）：
```
S_IDLE → S_CTX_LOAD → S_BATCH_INIT → S_LOAD_B → S_CI_INIT → S_LOAD_W → S_STREAM → S_DRAIN → S_CI_DONE
              ↑                              ↑__________________________________________|
              │                            (ci_idx 没跑完)
              │                                                                          ↓
              │                                                                    S_BATCH_DONE
              │                                                                          ↓
              │                                                                    S_DUMP_LDM ←── (4 PE LDM 写回 fmem)
              │                                                                          ↓
              └────────────── (layer_idx+1<num_layers)                       (再来一批 / 当前层完 → 下一层 / 全跑完 → S_DONE)
```
- **S_LOAD_B**: 一批一次，顺序读 NUM_PE 个 bias/scale 装到 PE Array。
- **S_CI_INIT**: ci 循环入口，准备权重读地址。
- **S_LOAD_W**: 针对当前 `ci_idx` 顺序读 NUM_PE×K 个权重；最后一拍拉 `conv_flush=1` 清空 conv1d sr。
- **S_STREAM**: 从 `feature_mem` 第 ci_idx 通道流式读 `N+K-1` 个像素喂 PE。
  - `mode_first = (ci_idx == 0) && conv_lat_done`
  - `mode_last  = (ci_idx == Ch_in-1) && conv_lat_done`
  - FAQR 据此决定"用 bias 初始化 / 累加 / 累加+量化输出"。
- **S_DRAIN**: 流水尾 1 拍，处理最后一个 partial。
- **S_CI_DONE**: 还有更多 ci → 回 `S_CI_INIT` 加载下一组权重；ci 跑完 → `S_BATCH_DONE`。
- **S_BATCH_DONE → S_DUMP_LDM**: 4×N 拍把当前批 4 个 PE 的 LDM[0..N-1]
  写回 `fmem[dst_base + co*FMEM_CH_STRIDE + PAD + n]`，下一层直接以 dst 当 src 拉数据；
  全部 batch 完 → 若 `layer_idx+1 < num_layers` 则 `layer_idx++ → S_CTX_LOAD`，否则 → `S_DONE`。
- **S_CTX_LOAD**: 从 `ctx_mem[layer_idx]` 读 80-bit ctx，拆出 N_in/Ch_in/Ch_out/src_base/
  dst_base/wbase/bbase 锁存到内部寄存器，进入 `S_BATCH_INIT` 跑当前层。

### 3.10 `csdae_ctx_mem.v` — 多层"配方表"（Step 3 新增）
- **是什么**：1 块 80-bit×NUM_LAYERS=19 深的小 BRAM。每条 ctx 描述一层执行参数：
  N_in / Ch_in / Ch_out / op_type / src_base / dst_base / weight_base / bias_base / relu_en。
- **形象**：菜单。tb 上电时把所有层的"菜谱"灌进去，控制器一道道按顺序做。
- **位段宏**：见 `csdae_defines.vh` 里的 `CSDAE_CTX_*(x)`。
- **接口**：async-read（与其它 mem 对齐），后门 `we/waddr/wdata` 给 tb 灌表。

### 3.11 `csdae_top.v` — 顶层
把 memories + schedule_ctrl + PE Array + 两个 pshuf 拼起来。当前对外开后门
`{f,w,b,c}mem_we_ext` 让 testbench 直接灌数据，方便 iverilog 仿真。
新增 `num_layers` 输入告诉控制器要跑几层；移除了直接传 N_in/Ch_in/Ch_out 端口（改从 ctx 读）。
后续把后门换成 AXI4-Lite + AXI4-DMA。

---

## 4. 模块连接图（文字版）

```
   ┌────────────┐  start    ┌─────────────────┐
   │ tb (后门)   │──────────▶│  schedule_ctrl  │
   └─┬───┬───┬──┘           │     (FSM)        │
     │   │   │              └────┬─────┬──────┘
     ▼   ▼   ▼                   │     │
   ┌────────────┐  raddr/rdata   │     │
   │ feature_mem│◀───────────────┘     │
   │ weight_mem │  (ASYNC 读)          │
   │ bias_mem   │◀──────raddr──────────┘
   └─────┬──────┘
         │ data + 权重 + bias_q/scale_q25 广播
         ▼
   ┌────────────────────────────────────────────┐
   │              csdae_pe_array                │
   │   ┌──┐ ┌──┐ ┌──┐ ┌──┐                      │
   │   │PE│ │PE│ │PE│ │PE│   (4 个，每个含       │
   │   └─┬┘ └─┬┘ └─┬┘ └─┬┘    conv1d+faqr+ldm)   │
   │     ld_rdata_pack                           │
   └─────┬────┬────┬────┬────────────────────────┘
         ▼    ▼    ▼    ▼
       (testbench 通过 ld_re_ext / ld_addr_ext 后门验证)
```

---

## 5. 跟着一条数据走一遍（推荐这一节读完就上手）

> 场景：第 1 层 Conv1D，**Ch_in=1, Ch_out=12, K=7, N=1024**（论文输入层）。

### 5.1 加载阶段 — "把 1024 个采样点 + 12 组权重 + 12 个 bias 灌进 RAM"

testbench 做的事（`tb/tb_csdae_top.v`）：
1. 写 `feature_mem`：先写 PAD=3 个 0 (左 zero-pad)，然后 1024 个 `x[i]`，再写 PAD=3 个 0 (右 zero-pad)。共 1030 字节（`STREAM_LEN = N+K-1`）。
2. 写 `weight_mem`：12 组 × 7 个 weight = 84 字节（**注意权重是逆序存的**, 见 BUGFIX.md #002）。
3. 写 `bias_mem`：12 个 96-bit 词，每个含 `{relu_en, out_zero, scale_q25, bias_q}`。

### 5.2 计算阶段 — "12 个输出通道，每批 4 个，共 3 批"

控制器 FSM 的循环：
```
for batch in {0, 4, 8}:                         # co_base
    Load 4 PE 的 weights  (S_LOAD_W, ~28 拍)
    Load 4 PE 的 bias/scale (S_LOAD_B, 4 拍)
    Stream 1030 输入 (S_STREAM):
        # 流水启动后约 STARTUP_LAT=15 拍, 开始出 partial
        for n in 0..1023:
            同时拉高 {acc_clr, acc_en, flush}
            FAQR 输出 quantized 8-bit, 写进 PE 的 LDM[n]
    Drain (S_DRAIN, 1 拍)
```

每一批的 4 个 PE 把 4 个不同 co 的卷积结果同时写到各自 LDM。

### 5.3 结果验证

testbench 在 `done` 之后挨个 PE 读 LDM[0..1023]，与 `tb/golden.hex` 比对。当前简化版 testbench 只能验证**最后一个 batch 的 4 个输出通道**（因为同一块 LDM 在每批 batch 都被覆盖一次）；要全验证，得改 PE 内 LDM 容量为 `Ch_out*N` 或在每批之间把 LDM dump 出来到 feature_mem。详见 `IMPLEMENTATION_NOTES.md` Step 1。

---

## 6. 怎么把这个工程跑起来

### 6.1 仿真（最快验证）

```bash
# 装 iverilog & numpy（一次即可）
sudo apt install -y iverilog gtkwave
pip install numpy

cd 2025_TCASI_VLSI_Compact_Shortcut_DAE/

# ── 单层 conv (默认)
./sim/run_sim.sh chin=1 chout=12   # 单层 ctx 驱动 + pshuf 端到端
./sim/run_sim.sh chin=12 chout=12  # 多通道累加

# ── pshuf 单元测试
./sim/run_sim.sh pshuf

# ── 多层 chain 测试 (Step 3 / Step 4)
./sim/run_sim.sh chain             # 4 层 conv→CS→concat→conv (默认 LAYERS) bit-level 校验
./sim/run_sim.sh chain_d           # P1.5 方案 D：11 层 N=128 微缩 U-Net (chain_d_layers.json)
./sim/run_sim.sh chain_a           # P1.5 方案 A：13 层 N=1024 论文规模 (chain_a_layers.json)

# ── 公用选项
./sim/run_sim.sh chin=1 wave       # + VCD
./sim/run_sim.sh clean             # 清理
```

期望看到（已验证）：
```
[1/4] generate golden ...
[golden] wrote input.hex weights.hex bias.hex golden.hex ...
[2/4] compile RTL + tb (iverilog -g2012) ...
[3/4] run simulation ...
[TB] BOOT @ 0
[TB] memories loaded @ 11325000
[TB] DONE asserted @ 43545000 (after 3221 cycles)
[TB] checking last batch (co=8..11)
[TB] check done: 0 / 4096 mismatches (last batch only, 4 of 12 co)
[TB] PASS (last batch matches golden)
```

### 6.2 上 Vivado（量产化第一步，详见 IMPLEMENTATION_NOTES.md Step 5/6）

1. 新建 Vivado 工程，目标板 PYNQ-Z2（论文用的）；
2. 把 `rtl/*.v` 加到 Sources，`tb/tb_csdae_top.v` 加到 Simulation Sources；
3. **替换 IP**（先不换也能仿真，换了能跑得更快/资源更紧）：
   - 4 块 mem 里的 reg array → Block Memory Generator IP；
   - `csdae_conv1d.v` 的乘法 → 显式 DSP48E1 / Multiplier IP；
   - 加一个 AXI4-Lite Slave（命令寄存器） + AXI4-DMA（特征/权重搬运）替换后门；
4. 用 IP Integrator 把 ZYNQ PS + AXI DMA + CSDAE 拼起来，PYNQ Python 侧通过 jupyter notebook 做实验。

---

## 7. 改动指引：常见需求落到哪里

| 我想…… | 改这里 |
|--------|-------|
| 把位宽从 8/8/32 改成 12/12/40 | `csdae_defines.vh` 里改 `CSDAE_DATA_W / WEIGHT_W / ACC_W` |
| 改 PE 数 (M=2, 8) | `csdae_defines.vh` 改 `CSDAE_NUM_PE` |
| 增加新的 ALU 操作（比如 GELU） | `csdae_faqr.v` 加 case + `csdae_defines.vh` 加 op 编码 |
| 支持 Ch_in>1 多通道累加 | 改 `csdae_schedule_ctrl.v`：在 ci 维加外循环，FAQR `acc_clr` 只在第一次 ci=0 时置 1，最后一次 ci=Ch_in-1 才 `flush` |
| 接入 Pixel-Shuffle / Unshuffle 层 | `csdae_schedule_ctrl.v` 加 `S_PSHUF` / `S_PUSHUF` 状态调用现有模块 |
| 接到自己的板子 | 写 `csdae_axi_lite_slave.v` + `csdae_axi_dma.v`，替换 `csdae_top.v` 的后门 |

---

## 8. 这个工程现在能跑到哪一步？

- ✅ Ch_in=1 (论文输入层) iverilog 仿真：`0/4096 mismatches`；
- ✅ **Step 1 完成**：Ch_in=1/2/4/12 全部 **0/12288 mismatches PASS**（FAQR.partial_mem 多通道
  累加 + schedule_ctrl 加 ci 外循环 + `pe_active` 启动期门控 + `FMEM_CH_STRIDE` 防溢出 +
  `batch_done/batch_ack` handshake 让 tb 每批快照 LDM）；
- ✅ **Step 2 完成**：pshuf 模块单测 + top 集成（fmem 读写口 mux + 直控接口），
  conv+pshuf 共用 fmem 端到端验证（C=2,N=8 ↔ C=4,N=4）round-trip bit-level 对齐；
  schedule_ctrl 状态机调用 pshuf 留 Step 3 一起做（需要 ctx_mem 触发 op）。
- ✅ **Step 3 完成**：S_DUMP_LDM（PE LDM → fmem 自动回写）+ `csdae_ctx_mem.v` +
  `S_CTX_LOAD` + `layer_idx` 循环；ctx 解出 N_in/Ch_in/Ch_out/src/dst/wbase/bbase；
  顶层移除 N_in/Ch_in/Ch_out 端口改为 `num_layers + cmem_we_ext` 后门；
  `golden_multilayer.py` + `tb_csdae_chain.v` 2 层 chain 测试 0/4096 PASS。
- ✅ **Step 4 完成**：op_type 分发 (CONV1D/PSHUF/PUSHUF/CONCAT)；ctx 触发 pshuf
  (`S_PSHUF/S_PSHUF_WAIT`) 与 concat (`S_CONCAT/S_CONCAT_WAIT`)；CS = conv1d K=7 但
  w[...,0] 非零 (软件层等价 1×1)；CTX 扩 88-bit 加 `src_b_base`；新增 `csdae_concat.v`；
  4 层 chain conv→CS→concat→conv `0/256` PASS。
- ⚠️ AXI / 论文实际 13 层网络 / FPGA 上板都还是骨架；
- ❌ 整模型端到端 + FPGA 上板还需要走完 `IMPLEMENTATION_NOTES.md` 里的 6 个 Step。

详细待办按优先级见 `TODO.md`，已踩过的坑见 `BUGFIX.md`，工程动态见 `LOG.md`。

**当前是一份"骨架完整、能仿真、单层数值与软件对齐"的工程**，足够你或后续 agent 继续填血肉。

---

## 9. 学习推荐顺序

1. 看本文第 5 节"跟着一条数据走"；
2. 打开 `tb/tb_csdae_top.v` 跟着 testbench 流程一行行对照 `csdae_schedule_ctrl.v`；
3. `./sim/run_sim.sh wave` 生成 VCD，重点看 `state, rd_cnt, conv_lat, out_cnt, in_valid, in_data, faqr.out_valid, ldm.we`；
4. 改一改参数（比如 `CSDAE_K=5`、`CSDAE_NUM_PE=2`）、重跑 golden + sim，看是否还过；
5. 然后挑 `IMPLEMENTATION_NOTES.md` 里的某一个 Step 入手做完善（Step 1 已完成，下一步推荐 Step 2 Pixel-Unshuffle / Pixel-Shuffle）。

祝玩得开心！
