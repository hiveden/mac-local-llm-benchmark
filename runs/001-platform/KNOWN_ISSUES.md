# 已知问题与数据注意事项

> RUN 01 测试过程中发现的实际问题，影响数据解读方式。
> 别人复现时必须阅读本文档，否则会误读数据。

## 数据审计结果（2026-04-06）

全部场景跑完后做的数据质量审计，发现 3 个严重问题和 3 个注意问题。
2026-04-05 实施 inter-round cleanup 后重跑全部场景，DA-1 已修复，DA-4 结论更新。

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

#### DA-4. B1 mlx-lm Turn 2 TTFT — 跨轮 cache 效应已消除

**修复前现象**: mlx-lm Turn 1 TTFT=310ms → Turn 2 TTFT=158ms，speedup 1.96x。当时解读为 mlx-lm prompt cache 识别共享前缀的正面结果。

**修复后现象**: 实施 inter-round cleanup 后，mlx-lm Turn 1 TTFT ≈ Turn 2 TTFT（158ms vs 157ms，speedup 1.01x）。之前的 1.96x 加速是因为 prompt cache 跨轮持续存在，并非多轮对话中的 intra-turn prefix 复用。

**结论**: cleanup 后，**三个平台均未在当前测试设计中展现 intra-turn cache 加速效果**。B1 场景需要重新设计才能测到真正的 prompt cache 效益（例如在同一请求内发送多轮）。

#### DA-5. A2 mlx-lm 所有轮次 response 完全相同

**现象**: 9 轮输出一字不差。

**原因**: temperature=0 确定性输出。不影响性能数据，tok/s 标准差极低（0.33）证实了一致性。

#### DA-6. Ollama KV cache 影响所有长 prompt 场景 — ✅ FIXED

已随 DA-1 一并修复。inter-round cleanup 确保每轮都是真实 prefill。

## 数据修正计划

| 补充场景 | 目的 | Prompt | 状态 |
|---------|------|--------|------|
| T1-token-count | A1 精确 token 数 | 同 A1 | ✅ 已完成 |
| T2-token-code | A2 精确 token 数 | 同 A2 | 待建 |
| A1b-nocache | 消除 Ollama KV cache 的真实 TTFT | 10 个不同 prompt | 待建（DA-1 修复后优先级降低） |

> DA-1 已通过 inter-round cleanup 修复，Ollama TTFT 现在是真实 prefill 数据。T2 和 A1b 仍可按需补充，但紧迫性降低。

## 技术选型问题

### Bash + 内嵌 Python

**现象**: lib.sh 用 Bash 做流程控制 + 内嵌 Python 做数据处理，导致变量注入风险、调试困难、多轮审核反复发现问题。

**RUN 02 改进**: 改为纯 Python（记录在 CLAUDE.md）。

### Token 估算逻辑

`len(content) // 2` 对中英混合内容方向错误。RUN 02 应用 tokenizer 本地计算或非流式 fallback。

## 数据字段可信度总结

| 字段 | Ollama | oMLX | mlx-lm | 说明 |
|------|--------|------|--------|------|
| ttft_ms | ✅ 精确 | ✅ 真实 prefill | ✅ 真实 prefill | DA-1 修复后 Ollama 也是真实 prefill |
| total_time_ms | ✅ 精确 | ✅ 精确 | ✅ 精确 | wall clock 计时 |
| tokens_generated | ✅ API 返回 | ⚠️ 估算 | ⚠️ 估算 | T1 场景补充精确值（仅 A1 prompt） |
| decode_tok_s | ✅ 可信 | ❌ 不可信 | ❌ 不可信 | 依赖 token 数，估算导致偏差 |
| memory_*_mb | ✅ ollama ps | ⚠️ ps RSS | ⚠️ ps RSS | DECISIONS.md #4 |
| completed | ✅ | ✅ | ✅ | 流式正常结束标记 |
| cache | ✅ 有记录 | ✅ 有记录 | N/A | 辅助参考 |

## 可信结论（基于当前数据可得出）

1. **A1 TTFT（短 prompt）**: oMLX 88ms < Ollama 150ms < mlx-lm 172ms — oMLX 短 prompt prefill 最快
2. **A3 TTFT（长 prompt）**: mlx-lm 176ms < oMLX 1332ms < Ollama 1523ms — mlx-lm 长 prompt TTFT 显著低于其他两个平台，可能与 prefill 流水线或 chat template 处理方式有关，具体原因待进一步分析
3. **总耗时对比**（A1/A3）: mlx-lm < Ollama < oMLX — mlx-lm 端到端最快
4. **Gemma4 引擎差距**（E1/E2）: oMLX (MLX) 总耗时比 Ollama (llama.cpp) 快 1.4-1.5x
5. **B1 缓存加速**: cleanup 后三个平台均未展现 intra-turn cache 加速，当前测试设计无法测到此效果
6. **tok/s**: 仅 Ollama 可信（~65 tok/s Qwen3.5, ~47 tok/s Gemma4），oMLX/mlx-lm 待 T 场景补充

## 不可信结论（需要补充数据）

1. **oMLX/mlx-lm 的 tok/s**: 估算值不可信
2. **A2 跨平台总耗时对比**: max_tokens 是否生效待确认
