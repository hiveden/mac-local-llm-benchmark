# A2: 代码生成单轮请求

## 目的

测试三个 MLX 平台处理代码生成任务的性能，中等长度生成场景。

## 前置条件

- thinking: false
- 测试前卸载所有平台模型，从冷启动开始

## Prompt

- system: "You are a Python expert."
- user: "用 Python 写一个 RAG 向量检索最小实现，包含文档切分、embedding、检索和生成四个步骤"
- expected_tokens: ~500

## 平台 × 模型

| Provider | Model | Engine | 量化 |
|----------|-------|--------|------|
| ollama | qwen3.5:35b-a3b-nvfp4 | MLX | nvfp4 |
| omlx | Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |
| mlx-lm | ~/.omlx/models/Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |

## 参数

- rounds: 10
- warmup: 1
- timeout: 120s
- max_tokens: 1024

## 核心指标

- TTFT (ms)
- decode tok/s
- 总耗时 (ms)
- 内存占用 (MB)
- 缓存状态

## 与 A1 的差异

- 有 system prompt（A1 没有）
- 生成长度约 500 tokens（A1 约 150）
- 可观察生成长度对 tok/s 稳定性的影响

## 已知限制

- 同 A1: 量化差异不可拆分
- 代码生成的 token 数波动较大（取决于模型选择的实现方式）
