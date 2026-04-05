# A3: 长文本总结单轮请求

## 目的

测试三个 MLX 平台处理长 prompt 的 prefill 性能。输入约 2000 tokens，输出约 200 tokens。

## 前置条件

- thinking: false
- 测试前卸载所有平台模型，从冷启动开始

## Prompt

- system: (无)
- user: 一篇约 2000 token 的 Transformer 技术文档 + "请用 200 字总结以上内容的核心要点。"
- expected_tokens: ~200

（完整 prompt 见 config.json）

## 平台 × 模型

| Provider | Model | Engine | 量化 |
|----------|-------|--------|------|
| ollama | qwen3.5:35b-a3b-nvfp4 | MLX | nvfp4 |
| omlx | Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |
| mlx-lm | ~/.omlx/models/Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |

## 参数

- rounds: 10
- warmup: 1
- timeout: 180s
- max_tokens: 512

## 核心指标

- TTFT (ms): **本场景最关键指标** — 长 prompt 的 prefill 耗时
- decode tok/s
- 总耗时 (ms)
- 内存占用 (MB)
- 缓存状态

## 与 A1/A2 的差异

- 输入长度大幅增加（~2000 tokens vs A1 的 ~20 tokens）
- TTFT 会显著高于 A1/A2（prefill 2000 tokens 需要时间）
- 第 1 轮（warmup）的 TTFT 会特别高（冷启动 + 长 prompt）
- 后续轮次 TTFT 是否下降，取决于平台的 KV cache 策略

## 已知限制

- 同 A1/A2: 量化差异不可拆分
- 长 prompt 的 prefill 性能受量化精度影响更大
