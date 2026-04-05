# T1: 非流式 Token 精确计数

## 目的

补充数据：部分平台（oMLX）在流式模式下不返回 completion_tokens，导致 A1-A3/E1-E2 的 tok/s 依赖估算值。

本场景用非流式请求对所有平台 × 所有 prompt 独立跑一遍，获取精确的 token 计数。分析阶段用 T1 数据修正流式场景的 tok/s。

## 设计原理

- 非流式请求返回完整的 usage（含 completion_tokens）
- 不采集 TTFT（非流式无法测 TTFT）
- 不替代流式场景，只提供 token 计数补充
- 完全独立运行，不依赖其他场景的数据

## Prompt

复用 A1 的短问答 prompt（与 A1 对齐，同 prompt 的 token 数才有修正意义）。

## 平台 × 模型

| Provider | Model |
|----------|-------|
| ollama | qwen3.5:35b-a3b-nvfp4 |
| omlx | Qwen3.5-35B-A3B-4bit |
| mlx-lm | ~/.omlx/models/Qwen3.5-35B-A3B-4bit |

## 参数

- rounds: 10
- warmup: 1
- timeout: 120s
- max_tokens: 512
- stream: false

## 核心指标

- completion_tokens（精确值）
- prompt_tokens
- total_time_ms（非流式总耗时，含 prefill + decode）

## 分析阶段使用方式

T1 的 median completion_tokens 可用于：
1. 修正 A1 中 token_source=estimated 的 tok/s
2. 验证 token_source=api 的平台返回值是否一致
