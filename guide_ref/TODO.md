# TODO

> 越靠前优先级越高。完成后立刻删除，超过两屏要清理。

## P1 — 网络结构 ✅ 全部完成

Step 1~4 全部跑通：单层 conv + Pixel-(Un)Shuffle + 多层 ctx 调度 + CS (1×1 conv) + Concat。

## P1.5 — 扩到论文 13 层完整网络 ✅ 完成（方案 D + A）

跑法：
- `./sim/run_sim.sh chain_d` — 11 层 N=128 微缩 U-Net，0/128 PASS。
- `./sim/run_sim.sh chain_a` — 13 层 N=1024 论文规模，0/512 PASS。

落地内容：见 IMPLEMENTATION_NOTES "Step 4.5"（已重写）+ LOG 2026-05-09 两条。
方案 B（per-layer 变长 stride）/ C（ping-pong）暂搁置，工程上不再需要。

## P2 — 上板路径 (Step 5~6)

- [ ] 把 `csdae_axi_lite_slave_stub.v` / `csdae_axi_dma_stub.v` 替换为真实实现（或拉 Xilinx IP）。
- [ ] mem 改回 sync 读 + schedule_ctrl 加 1 拍流水。
- [ ] Vivado 综合，把 `CSDAE_MAX_*` 调到论文实际尺寸看资源。

## P3 — 软件 / 数据

- [ ] PyTorch 写浮点 CS-DAE，跑 NSTDB 训练，导出量化后 8-bit 权重供硬件验证。
- [ ] PYNQ Python notebook 演示 demo（Step 5 完成后）。

---

## 近期完成（每过 2 周清理一次）

- 2026-05-08：工程骨架 + 第 1 层 conv1d (chin=1) 跑通 0/4096，Bug #001~#003 修复。
- 2026-05-08：CLAUDE.md 加 IP / 小白文档规则；axi_lite/dma stub 出炉。
- 2026-05-08：Step 1 (Ch_in>1 多通道累加) 完成，修 Bug #004 (fmem stride) + Bug #005
  (启动期 garbage)，chin=1/2/4/12 全 0/12288。
- 2026-05-08：Step 2 (Pixel-Shuffle/Unshuffle) 完成 — 修 Bug #006 (cp/np off-by-one)，
  pshuf 单测 + top 集成端到端 (16/16 + roundtrip 16/16)，全 chin 回归仍 PASS。
- 2026-05-08：**Step 3 (多层 chain) 完成** — `S_DUMP_LDM` 内化 + `csdae_ctx_mem.v` +
  `S_CTX_LOAD` + layer_idx 循环；ctx 解出 N_in/Ch_in/Ch_out/src_base/dst_base/wbase/bbase；
  top 移除 N_in/Ch_in/Ch_out 端口改为 num_layers + cmem 后门；新增
  `golden_multilayer.py` + `tb_csdae_chain.v`；2 层 chain (1→4 → 4→4, N=1024) 0/4096 PASS。
- 2026-05-08：**Step 4 第 1 阶段** — schedule_ctrl 加 op_type 分发 + `S_PSHUF/S_PSHUF_WAIT`，
  让 ctx 触发 pshuf；top 加 `ctrl_pshuf_*` mux（ctrl 优先于 tb 直控）；统一 pshuf 模块 stride
  到 `FMEM_CH_STRIDE`（修 bug #007）；3 层 conv→unshuf→conv chain 0/256 PASS。
- 2026-05-08：**Step 4 第 2 阶段 — CS + Concat 完成**。CTX 扩 88-bit 加 `src_b_base`；
  新增 `csdae_concat.v`；schedule_ctrl 加 `S_CONCAT` 状态；top 加 4 路 fmem mux；
  `golden_multilayer.py` 加 op="cs" (复用 conv1d K=7 但 w[...,0] 非零) + op="concat"；
  4 层 chain conv→CS→concat→conv 0/256 PASS，全套回归仍 PASS。**P1 完成**。
- 2026-05-09：**P1.5 方案 D 完成** — 11 层 N=128 微缩 U-Net 0/128 PASS，`chain_d_layers.json`
  + `tb_csdae_chain_d.v`；`golden_multilayer.py` 加 per-layer `b_range/scale` 覆盖避免 CS 链饱和。
- 2026-05-09：**P1.5 方案 A 完成** — 论文规模 13 层 N=1024 跑通 0/512 PASS。
  defines 加 `MAX_FMEM_CHANNELS=192` 脱钩 MAX_CHIN，fmem 198 KB；CTX 加宽到 112 bit
  (src/dst/sb_b 18 bit, wb 17 bit, bb 9 bit)；wmem/bmem depth 改 NUM_LAYERS×；
  `bias_mem` 改用 DEPTH 参数；`chain_a_layers.json` + `tb_csdae_chain_a.v`。
  Bug #008 (MAX_FMEM_CHANNELS=168 vs 实际 13 层需 182 槽位) 修复。
