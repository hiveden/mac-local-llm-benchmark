# B1: 多轮对话（缓存命中测试）

## 目的

测试三个平台在多轮对话场景下的缓存命中效果。
这是 oMLX 的核心差异化场景 — SSD KV cache 可跨轮复用 prefill 结果。

## 设计原理

多轮对话中，第二轮请求包含第一轮的完整历史作为 prefix。
如果平台有 KV cache，可以跳过 prefix 部分的重复 prefill，TTFT₂ 会显著低于无缓存的平台。

```
请求 1: messages = [user: "解释 RAG"]
  → 回答: <response_1>

请求 2: messages = [user: "解释 RAG", assistant: <response_1>, user: "给 3 个应用场景"]
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                    共享前缀 — 缓存命中则跳过 prefill
```

### 测试的是什么缓存

本场景测的是**同一会话内的 KV cache prefix 复用**：请求 1 和请求 2 在同一次模型驻留期间连续发送，Turn 2 的 prefix 与 Turn 1 完全重叠，观察平台是否能跳过重复 prefill。

每轮结束后会卸载模型并重新加载，确保下一轮的 Turn 1 是无缓存的干净状态。

**本场景不测试 oMLX 的 SSD 持久化缓存**（即"卸载模型 → 重启 → 缓存仍然命中"的能力）。验证 SSD 持久缓存需要不同的测试流程（卸载后不重新预热直接发请求），计划在后续 RUN 中覆盖。

### 缓存机制对比

- Ollama: KV cache snapshot（内存中，同一模型驻留时有效）
- oMLX: SSD KV cache（持久化到磁盘，跨会话有效）— 本场景仅验证会话内复用
- mlx-lm: 无持久化缓存（每次重新 prefill）

## 前置条件

- thinking: false
- 测试前卸载所有平台模型，从冷启动开始
- 不需要额外传参，缓存对应用层透明

## Prompt

轮 1:
- system: (无)
- user: "用一段话解释 RAG 的工作原理"

轮 2（追问，带历史）:
- user: "基于上面的解释，给出 3 个 RAG 在企业中的典型应用场景，每个场景用一句话描述"

## 流程（每次重复）

1. 发请求 1 → 记录 TTFT₁ / tok/s₁ → 拿到回答 response_1
2. 拼接历史 messages → 发请求 2 → 记录 TTFT₂ / tok/s₂
3. 清理（下一次重复从头开始）

## 平台 × 模型

| Provider | Model | Engine | 量化 |
|----------|-------|--------|------|
| ollama | qwen3.5:35b-a3b-nvfp4 | MLX | nvfp4 |
| omlx | Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |
| mlx-lm | ~/.omlx/models/Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |

## 参数

- rounds: 10（每轮包含 2 次请求）
- warmup: 1
- timeout: 180s
- max_tokens: 512

## 核心指标

- **TTFT₁ (ms)**: 第一轮首 token 延迟（基线）
- **TTFT₂ (ms)**: 第二轮首 token 延迟（缓存命中指标）
- **TTFT₂ / TTFT₁ 比值**: 缓存加速倍数
- decode tok/s（两轮分别记录）
- 内存占用
- 缓存状态（每轮采集）

## 预期结果

- oMLX 的 TTFT₂ 应显著低于 TTFT₁（SSD cache 命中）
- Ollama 的 TTFT₂ 可能也低于 TTFT₁（内存 KV cache）
- mlx-lm 的 TTFT₂ 应与 TTFT₁ 接近（无缓存，完整重算 prefix）

## 已知限制

- 同 A1: 量化差异不可拆分
- 第二轮的 prompt 长度 = 第一轮 prompt + 第一轮回答 + 追问，总长度不固定
- 缓存行为依赖平台内部实现，无法从外部精确控制
