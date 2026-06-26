# BUGFIX — 踩过的坑要写清楚，避免下次重蹈

每条按"现象 → 根因 → 修复 → 复发预防"四段写。

---

## #001 — `conv1d.out_valid` 比 `out_data` 晚 1 拍

**现象**：testbench 比对发现，第 1 个有效输出在波形里出现，但对比时跟 golden 错开 1 个位置。

**根因**：`csdae_conv1d.v` 里 `out_valid <= vshift[LATENCY-1]` 而 `out_data <= add_l4`。`vshift` 一共 N=LATENCY 位，`vshift[LATENCY-1]` 是 LATENCY 拍延迟，`add_l4` 这条路只有 LATENCY-1 拍延迟（最后一拍是 reg `out_data`），两者相差 1 拍。

**修复**：改成 `out_valid <= vshift[LATENCY-2]`。文件：`rtl/csdae_conv1d.v`。

**复发预防**：以后修改 conv1d 流水深度时，把 `out_valid` 的 vshift 索引和 `out_data` 的最后一级 reg 一起算，记下"两条路 reg 数应一致"。在代码注释里写清楚。

---

## #002 — 硬件实现的是 cross-correlation，不是 convolution（输出全部对不上）

**现象**：weights/inputs 都灌进去了，输出大量 0 或对不上 golden。

**根因**：`conv1d.v` 用 shift register `sr[0]<=in_data; sr[i]<=sr[i-1]`，这意味着 `sr[0]=最新输入, sr[K-1]=最旧输入`。MAC 算的是 `Σ sr[i]·w[i] = Σ in[t-i]·w[i]`，标准 DSP 称之为"cross-correlation"。Python `np.convolve(a,b)` 默认做的是"convolution"，对应 `Σ in[n+k]·w[k]`，要求 `w` 反过来才能等价。

**修复**：在 `scripts/golden_conv1d.py` 写 `weights.hex` 时把每个输出通道的 K 个权重**逆序**写入 wmem。这样硬件计算 `sum sr[i]*w_hw[i] = sum in[t-i]*w_golden[K-1-i] = sum in[t-K+1+k]*w_golden[k]`，与 golden 公式 `out[n] = sum in[n+k]*w[k]` 在 `n=t-K+1` 下完全等价。

**复发预防**：
1. 在 `csdae_conv1d.v` 文件头注释里明确写"硬件实现 cross-correlation；写权重时需逆序"。
2. golden 脚本里也写注释"weights.hex is reversed per-co"。
3. 任何 PyTorch → 8-bit 权重导出脚本都要做同样的逆序处理。

---

## #003 — 所有 mem 同步读导致 schedule_ctrl 第一次 consume 都是上一拍的旧值

**现象**：所有 PE 的 bias / scale_q25 / weights 都加载成 0 或 PE0 的值；FAQR 输出全 0；testbench 大量 mismatch (got=0 exp=非零)。

**根因**：`csdae_*_mem.v` 之前是同步读 (`always @(posedge clk) if (re) rdata <= mem[raddr];`)，rdata 比 raddr 晚 1 拍。但 `csdae_schedule_ctrl.v` 在加载阶段写法是"同拍发 raddr 同拍 consume rdata"，相当于读了"上一次 raddr 对应的旧数据"。fmem 流也有类似 off-by-one。

**修复**：把 4 块 mem 全部改成 ASYNC 读 (`assign rdata = mem[raddr]`，等价于 LUTRAM)。这样发 raddr 的下一拍 rdata 就是新值，schedule_ctrl 流水匹配。同时 schedule_ctrl 的 fmem 流去掉一级冗余 reg (`rd_valid_pipe_d`) 并把 `STARTUP_LAT` 从 16 改成 15。

**复发预防**：
1. `csdae_*_mem.v` 文件头注释明确写出"当前是 ASYNC 读，综合 BRAM 时改 sync 并补 1 拍 pipeline"。
2. `IMPLEMENTATION_NOTES.md` Step 6 里强调这一切换。
3. 任何新增 mem 都先决定"sync vs async"，并在 schedule_ctrl 流水里数清楚拍数。

---

## #004 — Ch_in>1 时 feature_mem 通道间寻址溢出（最后 K-1 个输出错位）

**现象**：Step 1 升级到 Ch_in>1 后，Ch_in=2 失败 11/4096、Ch_in=4 失败 19/4096，错误密集在 n=1018..1023（K-1=6 个位置）。Ch_in=1 仍 PASS。

**根因**：feature_mem 按 `ci_idx * MAX_FEAT + rd_cnt` 寻址，但 `STREAM_LEN = N + K - 1 = 1030 > MAX_FEAT = 1024`。所以 ci=0 通道流式读到 `rd_cnt = 1024..1029` 时，地址溢出到 ci=1 的存储区，读到的是 ci=1 的左 PAD 零 + 前 3 个数据，而不是 ci=0 的右 PAD 零。conv1d 后续 6 个有用输出（窗口包含这些"错位"输入）就全错。

**修复**：在 `csdae_defines.vh` 加 `CSDAE_FMEM_CH_STRIDE = MAX_FEAT + K - 1`，schedule_ctrl 和 testbench 都改用这个 stride 替代 MAX_FEAT 做"通道偏移"；`CSDAE_FMEM_DEPTH` 重新算成 `FMEM_CH_STRIDE * MAX_CHIN`。**已修复并验证（2026-05-08，Ch_in=1/2/4/12 全部 0/4096 mismatches）。**

**复发预防**：
1. 任何"按通道分块存"的 RAM 都要保证 stride ≥ 单通道实际写入长度（含 padding）。
2. 在 `csdae_defines.vh` 内对 stride 与 MAX_FEAT/STREAM_LEN 的关系写注释提醒。
3. PR 检查清单里加："改 K 或 PAD 时是否同步检查 STREAM_LEN ≤ FMEM_CH_STRIDE？"

---

## #005 — Ch_in>1 时 conv1d 启动期 garbage partial 污染 `partial_mem[0]`

**现象**：Ch_in=4 失败有一处 `co=11 n=0 got=1 exp=0`（pos=0 出错）。Ch_in=2 由于量化阈值刚好 round 一致，n=0 偶尔不报错但 acc 已经偏。

**根因**：FAQR 内 `partial_mem` 写条件是 `acc_en && !mode_last`。`acc_en` = conv1d.out_valid，**没有用启动期门控**。conv1d 流水启动后的前 K-1=6 拍输出是"sr 没填满的 garbage partial"。
- ci=0 时 `mode_first=1` 会让 pre_acc=bias，garbage 不影响最终值（被有用阶段的写入覆盖）。
- ci>0 时 `mode_first=0`，pre_acc=`partial_mem[pos_idx=0]`（已被 ci=0 写好的值），garbage 会被加进去再写回，污染 `partial_mem[0]`。后续 ci=Ch_in-1 读到的就是污染后的值。

**修复**：在 PE.v 给 FAQR 的 `acc_en` 加门控 `conv_out_valid & pe_active`，pe_active 由 schedule_ctrl 输出，仅在 `S_STREAM 且 conv_lat_done` 或 `S_DRAIN` 时为 1。schedule_ctrl 同步给 `mode_first/mode_last` 也用 `conv_lat_done` 门控保证一致。**已修复并验证（2026-05-08，Ch_in=1/2/4/12 全部 0/4096 mismatches）。**

**复发预防**：
1. 任何"接 conv1d.out_valid 喂下游累加器"的设计都必须用 `conv_lat_done` 或等价信号门控，不能直接当作"有效采样"。
2. 在 conv1d.v 文件头注释里加："out_valid=1 不代表 out_data 是 fully-windowed 的有用结果；前 K-1 拍是 sr 未填满的 garbage，调用方需自己用 `STARTUP_LAT` 计数器门控。"

---

## #006 — `pixel_(un)shuffle.v` cp/np 寄存器 off-by-one（dst 写入数据错位 1 步）

**现象**：Step 2 单测时发现，原版模块每写一个 dst 元素都"晚一拍"——即 `dst[k] <= mem[src_addr_for(k-1)]`，导致除了首尾以外全部错位。

**根因**：原实现里 `src_raddr` 是寄存器（NB 赋值），每拍取上一拍的 (cp,np) 算地址，而 (cp,np) 在同一拍尾部又非阻塞地推进了。结果：当前拍读到的 `src_rdata` 是上一组 (cp,np) 的数据，被写到当前拍已推进后的 `dst_waddr`，错位 1 步。

**修复**：改为 async-read + 同拍组合写：`src_raddr = comb(cp,np)` 输出（wire），mem 异步给出 `src_rdata`，同拍 `dst_we=1` `dst_waddr=comb(cp,np)` `dst_wdata=src_rdata`，然后时钟边沿推进 (cp,np)。把 `src_re/src_raddr/dst_we/dst_waddr/dst_wdata` 全部改成 `assign` 组合输出，clocked 块只管 cp/np/running/done。

**复发预防**：
1. 任何"读旧地址 → 写新地址"的搬运 FSM，必须想清楚"读地址寄存器"和"坐标寄存器"是否在同一拍同时更新。
2. 模块文件头注释里画一遍 cycle-by-cycle 表，把"src_raddr 何时稳定、src_rdata 何时可用、dst_we 何时拉高"写下来。
3. 新增搬运模块都先写单元 testbench（像 `tb_csdae_pshuf.v` 那样的 round-trip 比对）再集成进系统。

---

## #007 — pshuf 模块 stride 与 conv1d 输出布局不一致（多层 chain 错位）

**现象**：Step 4 把 conv→unshuffle→conv 串起来跑，最后一层 conv 输出错位，89/256 mismatches；但单层 conv 和 pshuf 单测都各自 PASS。

**根因**：通道间 stride 不统一。
- conv1d 的 `S_DUMP_LDM` 写出地址 = `dst_base + co * FMEM_CH_STRIDE + PAD + n`（stride=1030, 含 PAD=3）。
- pshuf 模块默认 `MAX_N = MAX_FEAT = 1024`，寻址 = `(c, n) → c*1024 + n`，**没有 PAD 偏移**。
- 当 schedule_ctrl 把 conv 的 dst 直接喂给 pshuf 当 src 时，c≥1 的通道偏移就错了 6 字节（K-1=2*PAD），数据被错位读到。

**修复**：
1. `csdae_pixel_unshuffle.v` / `csdae_pixel_shuffle.v` 把 `MAX_N` 默认改成 `CSDAE_FMEM_CH_STRIDE`（1030）。
2. `csdae_schedule_ctrl.v` 在 `S_PSHUF` 时把 `ctrl_pshuf_src_base / dst_base` 都加上 `PAD`，让 pshuf 实际地址 = `(base+PAD) + c*FMEM_CH_STRIDE + n`，正好对齐 conv 输出布局。
3. `tb_csdae_pshuf.v` / `tb_csdae_top.v` 内 pshuf 段也改用 `CSDAE_FMEM_CH_STRIDE` 做 stride。

**复发预防**：
1. **任何跨模块共享 fmem 的搬运/计算单元，stride 必须一致**（统一 = `FMEM_CH_STRIDE`），否则多通道偏移立刻错位。
2. 在 `csdae_defines.vh` 注释里说明：`FMEM_CH_STRIDE = MAX_FEAT + K - 1` 是工程内"通道分块存"的事实标准。
3. 新增模块如果引入"逐通道地址"必须复用此宏，不要写 `MAX_FEAT` 当 stride。

---

## #008 — `MAX_FMEM_CHANNELS=168` 装不下 13 层 chain，最后一层写出"out of bounds"

**现象**：方案 A 论文规模 13 层 N=1024 跑通后，比对 L12 输出全部 `got=x exp=-1`，
仿真器报告 `warning: returning 'bx for out of bounds array access mem[186433]`。
schedule_ctrl 的 `state=S_DONE`、`layer_idx=12`，所以 13 层都跑到了，
但 L12 的 dst_base=186430 落在了 fmem 数组之外，写不进去。

**根因**：
- 评估文档里第一版给的是"论文需要 ~165 KB → 168 槽位"，所以我先把
  `CSDAE_MAX_FMEM_CHANNELS` 设成了 168，`FMEM_DEPTH = 168 × 1030 = 173040`。
- 真实 13 层串接（conv1d → 3×(pushuf+cs) → 3×(pshuf+concat+cs)）的"槽位累加"
  按 golden_multilayer.py 的"sequential alloc"算下来是
  `Σ chin + last_chout = 181 + 1 = 182` 槽位。
- 168 < 182，最后两层（concat + cs）的 dst 区超出 `FMEM_DEPTH`，
  写操作落到 `mem[]` 越界，仿真器静默丢弃。

**修复**：把 `CSDAE_MAX_FMEM_CHANNELS` 提到 **192**（≥ 182，留 buffer），
`FMEM_DEPTH = 192 × 1030 = 197760`。一行改完，0/512 PASS。

**复发预防**：
1. 设 `MAX_FMEM_CHANNELS` 时，**必须按"sequential alloc 公式" `Σ chin_i + chout_last` 估**，
   不是按"6 个 encoder 输出 × 24 ≈ 145 KB"那种粗估。
   `golden_multilayer.py` 的 `multilayer_dump.txt` 里最后一行 `dst_base + chout_last × stride`
   就是真值，配置完层表先看一眼。
2. tb 里写"fmem 全清零循环"时，循环上限用 `CSDAE_FMEM_DEPTH`，所以越界访问会被
   iverilog 的 `out of bounds array access` warning 抓到——遇到 `got=x` 大面积全
   X，**第一反应去 stderr 找这条 warning**。
3. 调整 `MAX_FMEM_CHANNELS` 是 1 行 defines，但**记得跟着检查** `FAW = $clog2(FMEM_DEPTH)`
   的位宽是否够；CTX 里 `src_base/dst_base/src_b_base` 字段位宽是否还兜得住。
   工程目前 18 bit 兜到 262143（`MAX_FMEM_CHANNELS ≤ 254`），再扩要拓 ctx。
