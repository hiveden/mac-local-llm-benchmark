# A1: 短问答单轮请求

## 目的

测试三个 MLX 平台处理短问答的裸速，最基础的性能基准。

## 前置条件

- thinking: false（关闭 thinking 模式）
- 测试前卸载所有平台模型，从冷启动开始
- 每个 provider 独立清理环境后再测

## Prompt

- system: (无)
- user: "用一段话解释 RAG 的工作原理"
- expected_tokens: ~150

## 平台 × 模型

| Provider | Model | Engine | 量化 |
|----------|-------|--------|------|
| ollama | qwen3.5:35b-a3b-nvfp4 | MLX | nvfp4 |
| omlx | Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |
| mlx-lm | ~/.omlx/models/Qwen3.5-35B-A3B-4bit | MLX | group-wise 4bit |

## 参数

- rounds: 10
- warmup: 1（第 1 轮不计入统计）
- timeout: 120s
- max_tokens: 512

## 核心指标

- TTFT (ms): 首 token 延迟
- decode tok/s: 解码速度
- 总耗时 (ms)
- 内存占用 (MB)
- 缓存状态

## 已知限制

- Ollama 用 nvfp4 量化，oMLX/mlx-lm 用 group-wise 4bit，量化差异会影响速度
- 速度差异 = 平台封装开销 + 量化算法差异，两者不可拆分
