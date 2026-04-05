# 已知问题与数据注意事项

> RUN 01 测试过程中发现的实际问题，影响数据解读方式。

## P0 — 影响数据准确性

### 1. oMLX/mlx-lm 流式模式不返回 token 计数

**现象**: oMLX 和 mlx-lm 的 SSE 流式响应中不包含 `usage.completion_tokens`，代码 fallback 到 `len(content) // 2` 估算。

**影响**:
- `token_source: estimated` 的 tok/s 数据**不可信**
- A2 实测：Ollama 3346 字符 = 1024 tokens (API)，oMLX 3233 字符 = 1616 tokens (估算)
- 估算值比实际偏高 ~50%，导致 tok/s 虚高

**处理**:
- T1 场景用非流式请求独立采集精确 token 数
- 分析阶段：`token_source=estimated` 的 tok/s 不参与对比，用 T1 数据修正
- TTFT 和总耗时不受影响，始终精确

**根因**: `len(content) // 2` 对中英混合内容（尤其代码）严重高估。中文 ~1-2 token/字符，代码符号 ~1 token/字符，除以 2 方向错误。

**RUN 02 改进方向**: 改用纯 Python 脚本，用 tokenizer 本地计算 token 数，或在非流式 fallback 中获取精确值。

### 2. Bash + 内嵌 Python 技术选型问题

**现象**: lib.sh 用 Bash 做流程控制 + 内嵌 Python 做数据处理，导致：
- 变量注入风险（shell 变量直接插入 Python 字符串）
- 调试困难（两层语言交错）
- 多轮代码审核中反复发现引号、转义、作用域问题

**影响**: 增加了项目搭建时间，但经过多轮审核后当前代码功能正确。

**RUN 02 改进**: 已确认改为纯 Python（记录在 CLAUDE.md）。

### Token 数据修正方案

oMLX/mlx-lm 流式场景的 tok/s 显示 N/A（estimated 数据不参与统计）。精确 token 数据通过独立场景 T1 补充：

```
T1-token-count/           ← 独立场景，非流式请求
├── DESIGN.md             ← 设计说明
├── config.json           ← 同 A1 prompt
├── run.sh                ← 独立运行，不依赖其他场景
└── data/                 ← 精确 completion_tokens
```

analyze.py 的处理流程：
1. 流式场景（A1-A3/E1-E2）: `token_source=estimated` 的 tok/s 输出 N/A
2. T1 场景: 独立输出精确 token 数（`token_analysis.md`）
3. 修正 tok/s: `T1 tokens / (流式总耗时 - TTFT)` 作为近似值
4. 报告中明确标注修正值和原始值的区别

## P1 — 需要注意的数据特征

### 3. Ollama TTFT 显著低于 oMLX/mlx-lm

A1 数据：Ollama 50ms vs oMLX 101ms vs mlx-lm 154ms。

**可能原因**:
- Ollama 用 `/api/chat`（原生 API），oMLX/mlx-lm 用 `/v1/chat/completions`（OpenAI 兼容层），API 路径不同
- Ollama 的 KV cache snapshot 机制可能在重复 prompt 时加速 prefill
- 三个平台的量化方式不同（nvfp4 vs group-4bit），prefill 计算量不同

**处理**: 在报告中说明 TTFT 差异的多种可能原因，不做单一归因。

### 4. mlx-lm warmup 轮 TTFT 极高

mlx-lm 首轮 TTFT 通常 1500-2500ms（A1: 2432ms, A2: 1684ms），后续稳定在 150-170ms。

**原因**: 首次推理触发 MLX JIT 编译。虽然 warmup_provider 已发了预热请求，但预热 prompt（"hi"）和测试 prompt 的计算图可能不同。

**处理**: warmup 轮标记为 `is_warmup: true`，analyze.py 自动排除。

### 5. 每轮 response 内容不固定

同一个 prompt，每轮回答内容和长度都不同（模型生成有随机性）。这导致：
- token 数波动：A1 ollama 88-130 tokens
- 总耗时波动：与 token 数正相关
- tok/s 相对稳定（A1 ollama stdev 0.21）

**处理**: 用中位数而非均值，10 轮样本足够消除异常值。

## 数据字段可信度总结

| 字段 | Ollama | oMLX | mlx-lm | 说明 |
|------|--------|------|--------|------|
| ttft_ms | ✅ 精确 | ✅ 精确 | ✅ 精确 | 流式计时，三平台一致 |
| total_time_ms | ✅ 精确 | ✅ 精确 | ✅ 精确 | wall clock 计时 |
| tokens_generated | ✅ API 返回 | ⚠️ 估算 | ⚠️ 估算 | T1 场景补充精确值 |
| decode_tok_s | ✅ 可信 | ❌ 不可信 | ❌ 不可信 | 依赖 token 数，估算导致虚高 |
| memory_*_mb | ✅ ollama ps | ⚠️ ps RSS | ⚠️ ps RSS | DECISIONS.md #4 |
| completed | ✅ | ✅ | ✅ | 流式正常结束标记 |
| cache | ✅ 有记录 | ✅ 有记录 | N/A | 辅助参考 |
