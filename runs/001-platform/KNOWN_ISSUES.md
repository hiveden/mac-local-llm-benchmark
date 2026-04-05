# 已知问题与数据注意事项

> RUN 01 测试过程中发现的实际问题，影响数据解读方式。
> 别人复现时必须阅读本文档，否则会误读数据。

## 数据审计结果（2026-04-06）

全部场景跑完后做的数据质量审计，发现 3 个严重问题和 3 个注意问题。
2026-04-05 实施 inter-round cleanup 后重跑全部场景，DA-1 已修复，DA-4 结论更新。
2026-04-05 发现 mlx-lm prompt cache 问题（DA-7），修复后第三次重跑全部场景。
2026-04-06 第四轮: mlx-lm 改回不重启 server（--prompt-cache-size 0 已禁用 cache），只重跑 mlx-lm 数据，Ollama/oMLX 数据不动。

### 🔴 严重问题

#### DA-1. Ollama KV cache 导致 TTFT 跨平台不可比 — ✅ FIXED

**现象**: Ollama 对重复 prompt 有 KV cache snapshot 机制。同一 prompt 跑 10 轮，第 1 轮（warmup）TTFT 反映真实 prefill 时间，第 2-10 轮命中 cache，TTFT 骤降。

**修复**: 在 `lib.sh` 中新增 `inter_round_cleanup` 函数，每轮测试之间清理 Ollama KV cache（卸载并重新加载模型），确保每轮都是真实 prefill。

**修复前后 TTFT 对比（median）**:

| 场景 | 修复前（cache hit） | 修复后（真实 prefill） | 说明 |
|------|---------------------|------------------------|------|
| A1 短 prompt | ~50ms | ~150ms | 3x 差距，之前严重低估 |
| A3 长 prompt | ~58ms | ~1523ms | 26x 差距，之前完全失真 |
| E2 Gemma4 长 prompt | ~274ms | ~2693ms | 10x 差距 |

**结论**: 修复后 Ollama TTFT 反映真实 prefill 性能，跨平台 TTFT 对比恢复有效。

#### DA-2. oMLX/mlx-lm 流式模式不返回 token 计数

**现象**: oMLX 和 mlx-lm 的 SSE 流式响应不包含 `usage.completion_tokens`，代码 fallback 到 `len(content) // 2` 估算。

**实测数据**:
- A2: Ollama 3346 字符 = 1024 tokens (API)，oMLX 3233 字符 = 1616 tokens (估算)
- 相似字符数 → 实际 token 数应相近 → 估算值偏离 ~50%

**影响**:
- `token_source: estimated` 的 **tok/s 数据不可信，summary.md 中显示 N/A**
- T1 场景提供了 A1 prompt 的精确 token 数（独立采集）
- A2/A3/E1/E2 的精确 token 数尚未补采

**处理**:
- T1 数据仅适用于 A1 场景（同 prompt）
- **计划新增 T2-token-code 场景**: A2 prompt 的非流式 token 计数
- analyze.py 已过滤 estimated 数据，tok/s 显示 N/A
- 可信指标：TTFT 和总耗时（不依赖 token 数）

#### DA-3. A2 场景 max_tokens 可能在 oMLX/mlx-lm 上未生效

**现象**: Ollama 每轮恰好 1024 tokens（命中 max_tokens 上限），oMLX/mlx-lm 的 response 字符数与 Ollama 接近但无法确认实际 token 数。

**影响**:
- 如果 max_tokens 未生效，三平台生成量不一致，总耗时对比不公平
- 无法确认，因为 oMLX/mlx-lm 不返回精确 token 数

**处理**:
- 需要 T2 场景确认 A2 prompt 下各平台的实际 token 数
- 当前 A2 数据的总耗时对比需谨慎解读

### 🟡 注意问题

#### DA-4. B1 多轮 cache 效应 — 数据更新（第三次重跑）

**修复前现象**: mlx-lm Turn 1 TTFT=310ms → Turn 2 TTFT=158ms，speedup 1.96x。当时解读为 mlx-lm prompt cache 识别共享前缀的正面结果。

**第四轮数据**（mlx-lm 不重启 server，`--prompt-cache-size 0` 禁用 cache）:
- **mlx-lm**: Turn1 205ms → Turn2 407ms，**speedup 0.5x**（无加速，Turn2 更长 context 导致更长 prefill，符合预期）
- **Ollama**: Turn1 133ms → Turn2 356ms，speedup 0.37x（同上）
- **oMLX**: Turn1 89ms → Turn2 304ms，speedup 0.29x（同上）

**结论**: 禁用 prompt cache 后，**三平台均无 intra-turn cache 加速**，Turn2 TTFT 均高于 Turn1（更长 context → 更长 prefill），行为一致。第三轮观察到的 mlx-lm 3.96x 加速是因为当时还未禁用 prompt cache。

#### DA-5. A2 mlx-lm 所有轮次 response 完全相同

**现象**: 9 轮输出一字不差。

**原因**: temperature=0 确定性输出。不影响性能数据，tok/s 标准差极低（0.33）证实了一致性。

#### DA-7. mlx-lm prompt cache 导致 TTFT 虚低 — ✅ FIXED

**现象**: mlx-lm server 默认 `--prompt-cache-size` 非零，会缓存重复 prompt 的 prefill 结果。轮间清理跳过了 mlx-lm（误以为无跨请求缓存），导致 round_02+ 命中 prompt cache。

**修复（两部分）**:
- 启动 mlx-lm 时加 `--prompt-cache-size 0`（禁用 prompt cache）
- `inter_round_cleanup` 对 mlx-lm 改为 `return 0`（不重启 server，避免 ~1.4s JIT 开销）

**TTFT 演变（median）**:

| 场景 | 第二轮（cache hit） | 第三轮（重启，JIT 开销） | 第四轮（不重启，公平） |
|------|---------------------|------------------------|---------------------|
| A1 短 prompt | ~172ms | ~1573ms | 204ms |
| A3 长 prompt | ~176ms | ~2806ms | 1619ms |
| A2 code | — | ~1624ms | 266ms |

#### DA-6. Ollama KV cache 影响所有长 prompt 场景 — ✅ FIXED

已随 DA-1 一并修复。inter-round cleanup 确保每轮都是真实 prefill。

## 数据修正计划

| 补充场景 | 目的 | Prompt | 状态 |
|---------|------|--------|------|
| T1-token-count | A1 精确 token 数 | 同 A1 | ✅ 已完成 |
| T2-token-code | A2 精确 token 数 | 同 A2 | 待建 |
| A1b-nocache | 消除 Ollama KV cache 的真实 TTFT | 10 个不同 prompt | 待建（DA-1 修复后优先级降低） |

> DA-1 和 DA-7 均已修复。第四轮为最终数据：Ollama/oMLX 沿用第三轮数据，mlx-lm 第四轮重跑（不重启 server + 禁用 prompt cache）。T2 和 A1b 仍可按需补充，但紧迫性降低。

## 技术选型问题

### Bash + 内嵌 Python

**现象**: lib.sh 用 Bash 做流程控制 + 内嵌 Python 做数据处理，导致变量注入风险、调试困难、多轮审核反复发现问题。

**RUN 02 改进**: 改为纯 Python（记录在 CLAUDE.md）。

### Token 估算逻辑

`len(content) // 2` 对中英混合内容方向错误。RUN 02 应用 tokenizer 本地计算或非流式 fallback。

## 数据字段可信度总结

| 字段 | Ollama | oMLX | mlx-lm | 说明 |
|------|--------|------|--------|------|
| ttft_ms | ✅ 精确 | ✅ 真实 prefill | ✅ 精确（不含 JIT） | DA-1 修复后三平台均为真实 prefill |
| total_time_ms | ✅ 精确 | ✅ 精确 | ✅ 精确 | wall clock 计时 |
| tokens_generated | ✅ API 返回 | ⚠️ 估算 | ⚠️ 估算 | T1 场景补充精确值（仅 A1 prompt） |
| decode_tok_s | ✅ 可信 | ❌ 不可信 | ❌ 不可信 | 依赖 token 数，估算导致偏差 |
| memory_*_mb | ✅ ollama ps | ⚠️ ps RSS | ⚠️ ps RSS | DECISIONS.md #4 |
| completed | ✅ | ✅ | ✅ | 流式正常结束标记 |
| cache | ✅ 有记录 | ✅ 有记录 | N/A | 辅助参考 |

## 可信结论（基于当前数据可得出）

1. **A1 TTFT（短 prompt）**: oMLX 87ms < Ollama 133ms < mlx-lm 204ms — oMLX prefill 最快
2. **A3 TTFT（长 prompt）**: oMLX 1317ms < Ollama 1455ms < mlx-lm 1619ms — 同趋势
3. **总耗时**: mlx-lm 最快（A1: 1293ms, A2: 11710ms, A3: 3025ms），decode 速度最快
4. **prefill 差值（A3-A1）一致**: Ollama 1322ms, oMLX 1230ms, mlx-lm 1415ms — MLX 引擎 prefill 速度本身无显著差异
5. **Gemma4 跨引擎（E1/E2）**: oMLX (MLX) vs Ollama (llama.cpp) — E1 总耗时 oMLX 1706ms vs Ollama 2512ms; E2 总耗时 oMLX 3740ms vs Ollama 7659ms — MLX 引擎快 1.5-2x
6. **B1 多轮**: 禁用 cache 后三平台均无 intra-turn 加速，Turn2 TTFT > Turn1（更长 context），行为一致
7. **tok/s**: 仅 Ollama 可信（~66 tok/s Qwen3.5, ~47 tok/s Gemma4），oMLX/mlx-lm 待 T 场景补充

## 不可信结论（需要补充数据）

1. **oMLX/mlx-lm 的 tok/s**: 估算值不可信（token_source: estimated）
2. **A2 跨平台总耗时对比**: max_tokens 是否生效待确认

## 数据版本历史

| 轮次 | Git Commit | Ollama | oMLX | mlx-lm | 问题 |
|------|-----------|--------|------|--------|------|
| 第一轮 | 280b59d | KV cache hit | ✅ | prompt cache hit | 两平台有缓存 |
| 第二轮 | bd7256a | ✅ 清理后 | ✅ | prompt cache hit | mlx-lm 缓存未发现 |
| 第三轮 | aab802f | ✅ | ✅ | JIT 冷启动 1.4s | 过度矫正 |
| 第四轮 | 8486b87 | ✅ (不动) | ✅ (不动) | ✅ 公平 TTFT | 最终版 |
