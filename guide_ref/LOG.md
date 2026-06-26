# LOG

每条 1–3 行：日期 + 做了什么 + 当前状态。

- 2026-05-08：建工程骨架（rtl/tb/sim/scripts/docs + 6 份 markdown），所有数字参数化到 `csdae_defines.vh`。
- 2026-05-08：写完 `conv1d / faqr / ldm / pe / pe_array / *_mem / pixel_(un)shuffle / schedule_ctrl / top` 共 11 个 RTL 模块；提交 `tb_csdae_top.v` + `golden_conv1d.py` + `run_sim.sh`。
- 2026-05-08：第 1 次仿真：FAIL，2556/4096 mismatches。根因：(1) conv1d out_valid/out_data 错位 1 拍；(2) 卷积 vs 互相关方向不一致；(3) fmem read pipe off-by-one。
- 2026-05-08：修：conv1d valid 用 `vshift[LATENCY-2]`；权重写 hex 时逆序；testbench 预先 PAD；mem 全部改 ASYNC 读；STARTUP_LAT 重算 = 2+(K-1)+LATENCY = 15。再跑：**0/4096 mismatches，PASS**。状态：第 1 层骨架完成。
- 2026-05-08：CLAUDE.md 加规则 7（IP 处理）和规则 8（小白友好文档）。给 conv1d / *_mem.v 加 `[IP]` 头注释；新建 `csdae_axi_lite_slave_stub.v` 和 `csdae_axi_dma_stub.v`（接口推测 + 时序文档）。
- 2026-05-08：开始 Step 1（Ch_in>1 多通道累加）。重写 FAQR 加内部 `partial_mem`；改控制器 `acc_clr/flush` → `mode_first/mode_last + pos_idx`；schedule_ctrl 加 `ci_idx` 外循环；golden / tb / run_sim 全部参数化 Ch_in。Ch_in=1 backward compat 通过 (0/4096)；Ch_in=2 失败 11/4096，Ch_in=4 失败 19/4096，错误集中在 n=1018..1023 + n=0。
- 2026-05-08：定位 Bug #004：`STREAM_LEN(=1030) > MAX_FEAT(=1024)`，schedule_ctrl 用 `ci*MAX_FEAT` 寻址 feature_mem 时溢出到下一 ci 区，污染最后 K-1 个输出。已加 `CSDAE_FMEM_CH_STRIDE` 宏。还有 Bug #005（启动期 garbage partial 污染 `partial_mem[0]`）待修。状态：Ch_in>1 调试中。
- 2026-05-08：修 Bug #004（schedule_ctrl + tb + `CSDAE_FMEM_DEPTH` 全部改用 `FMEM_CH_STRIDE`）+ Bug #005（schedule_ctrl 新增 `pe_active`，仅 `S_STREAM&&conv_lat_done` 或 `S_DRAIN` 拉高；PE 把 FAQR.acc_en 改为 `conv_out_valid & pe_active`）。Ch_in=1/2/4/12 全部 0/4096 mismatches PASS。Step 1 完成。
- 2026-05-08：schedule_ctrl 加 `batch_done/co_base_out/batch_ack` 三信号 handshake，S_BATCH_DONE 等 ack 才前进；testbench 每批触发后用后门读 LDM 把 NUM_PE×N 输出快照到 `out_all[CH_OUT*N]`，最终全 12 个 co 比对。Ch_in=1/2/4/12 全部 0/12288 mismatches PASS。P0 收尾完成。
- 2026-05-08：Step 2 — 重写 `csdae_pixel_(un)shuffle.v` 为 async-read + 同拍写组合实现（修原版 cp/np 寄存器 off-by-one，详见 BUGFIX #006）；新增 `tb_csdae_pshuf.v` 单测，`run_sim.sh` 加 `pshuf` target；(C=2,N=8) ↔ (C=4,N=4) round-trip 0/16+0/16 PASS。
- 2026-05-08：Step 2 集成完成 — top 例化两个 pshuf，加 `pshuf_op/N/C/src_base/dst_base` 直控端口；feature_mem 读写口 mux；tb 在 conv 测试后追加端到端 pshuf 段，三段 base (13312/17408/21504) 不与 conv 输入冲突；chin=1/2/4/12 conv+pshuf 全 PASS。schedule_ctrl 状态机集成留 Step 3 一起做（需要 ctx_mem 触发 op）。
- 2026-05-08：Step 3 第 1 阶段 — schedule_ctrl 加 `S_DUMP_LDM` 状态把 PE LDM 写回 feature_mem（地址=output_base+co*FMEM_CH_STRIDE+PAD+n，多层 chain 直接以 dst 当 src）；top 加 `output_base` 端口和 dump/pshuf/ext 三路 mux；废弃 batch_ack handshake；tb 直接从 fmem 读输出比对。chin=1/2/4/12 全 PASS。下阶段：ctx_mem + S_CTX_LOAD + 2 层 chain 测试。
- 2026-05-08：Step 3 第 2 阶段 — Task #9~#16 串完。新增 `csdae_ctx_mem.v`（80-bit×19 async-read），schedule_ctrl 加 `S_CTX_LOAD` 状态 + `layer_idx` 外循环，`N_in/Ch_in/Ch_out/src_base/dst_base/wbase/bbase` 全部从 ctx 解出来；top 移除 N_in/Ch_in/Ch_out/output_base 端口，改为 `num_layers + cmem_we_ext` 后门写。新增 `golden_multilayer.py`（多层串接量化 conv1d 参考）+ `tb_csdae_chain.v` 2 层 chain 测试 + `run_sim.sh chain` target。**单层回归 chin=1/2/4/12 仍 0/12288 PASS；2 层 chain (1→4 → 4→4, N=1024) 0/4096 PASS**。Step 3 完成。
- 2026-05-08：Step 4 第 1 阶段 (Task #18~#22) — schedule_ctrl 加 op_type 分发 + `S_PSHUF/S_PSHUF_WAIT` 状态，由 ctx 触发 pshuf 模块；top 加 `ctrl_pshuf_*` 输入并 mux（ctrl 优先于 tb 直控）；pshuf 模块 stride 默认改为 `FMEM_CH_STRIDE`（避开多层 chain 中 conv 输出 PAD 偏移与 pshuf 寻址不一致 bug #007）；`golden_multilayer.py` 支持 conv1d / pushuf / pshuf 三种 op；`tb_csdae_chain.v` 默认改为 3 层 conv→unshuffle→conv (1→4 → 4→8 → 8→4)。**3 层 chain 0/256 PASS；pshuf 单测 + conv chin=1/2/4/12/8 全部回归 0/12288 PASS**。
- 2026-05-08：**Step 4 第 2 阶段 (Task #24~#31) — CS + Concat 完成**。CTX 扩到 88-bit 加 `src_b_base` 字段；新增 `csdae_concat.v` (channel-wise async-read+同拍写)；schedule_ctrl 加 `S_CONCAT/S_CONCAT_WAIT` 状态；top 加 4 路 fmem mux (concat>pshuf>dump>ext)；`golden_multilayer.py` 加 op="cs" (硬件复用 conv1d K=7 但 w[...,0] 非零) 和 op="concat" (用 layer_outputs+src_b_layer 索引)；tb_csdae_chain 跑 4 层 conv→CS→concat→conv (1→4→4 + L0 → 8 → 4) **0/256 PASS**。全套回归 (pshuf 单测 + conv chin=1/4/12 + chain) 全 PASS。Step 4 完成。
- 2026-05-08：fmem 容量评估 — 论文 13 层完整网络（24 ch encoder × 6 + CS shortcut）总需 ~165 KB，当前 fmem_depth=24720 单个 24-ch 层就占满。详见 IMPLEMENTATION_NOTES "Step 4.5"。给出 4 个待选方案 (A 扩 MAX_CHIN / B 变长 stride / C ping-pong / D 缩小测试)，推荐先 D 后 A。本回合到此暂停，等用户决定方向再继续。
- 2026-05-09：**P1.5 方案 D 完成** — 新增 `scripts/chain_d_layers.json` (11 层 N=128 微缩 U-Net：conv1d×1+cs×7+pushuf+pshuf+concat) + `tb_csdae_chain_d.v` + `run_sim.sh chain_d` target；`golden_multilayer.py` 加 per-layer `b_range/scale` 覆盖（CS 链不再用 ×7 默认 scale 导致饱和）。fmem 用满 24×1030=24720 字节。**0/128 PASS**，全回归仍 PASS。
- 2026-05-09：**P1.5 方案 A 完成** — 论文规模 13 层 N=1024 跑通。
  defines 改：新增 `CSDAE_MAX_FMEM_CHANNELS=192`，`FMEM_DEPTH = STRIDE × MAX_FMEM_CHANNELS`（脱钩 MAX_CHIN）；
  `WMEM_DEPTH = NUM_LAYERS × MAX_CHIN × MAX_CHOUT × K`，`BMEM_DEPTH = NUM_LAYERS × MAX_CHOUT`（多层串接需要）；
  `bias_mem` 改用 `DEPTH` 参数；`top.v / schedule_ctrl / tb_*` 的 `BAW` 改用 `$clog2(BMEM_DEPTH)`。
  CTX 扩到 112 bit：src/dst/sb_b 由 15 → 18 bit，wb 由 12 → 17 bit，bb 由 5 → 9 bit，hex 文件由 22 → 28 hex 位；
  `tb_csdae_top.v` 与 `golden_multilayer.py` 的 make_ctx 同步更新。
  新增 `chain_a_layers.json` (13 层：conv1d → 3×(pushuf+cs) 编码器 → 3×(pshuf+concat+cs) 解码器，含两条 CS shortcut) + `tb_csdae_chain_a.v` + `run_sim.sh chain_a` target。
  fmem 用 ~187 KB / 198 KB；171K cycles。**0/512 PASS**。conv chin=1/12 + pshuf + chain (4 层) + chain_d (11 层) + chain_a (13 层) 全部 PASS。**P1.5 完成。**
