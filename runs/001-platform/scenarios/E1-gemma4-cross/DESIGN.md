# E1: Gemma4-26B 跨引擎对比

## 目的

展示同一模型在不同推理引擎下的性能差距。
Ollama 对 Gemma4 没有 MLX 支持（走 llama.cpp Metal），oMLX 走 MLX 原生。
这是 RUN 01 中最能体现"MLX 加速缺失的真实差距"的场景。

## 背景

Ollama 0.19 引入 MLX 引擎，但截至 0.20.2 仅支持 Qwen3.5 的 nvfp4 格式。
Gemma4 在 Ollama 上仍使用 llama.cpp (Q4_K_M, Metal 加速)。
oMLX 对 Gemma4 有原生 MLX 支持 (group-wise 4bit)。

这组数据直接回应评论区"Ollama MLX 是不是对所有模型都有效"的质疑。

## 前置条件

- thinking: false（Gemma4 不是 thinking 模型，此参数无影响）
- 测试前卸载所有平台模型，从冷启动开始

## Prompt

与 A1 相同:
- system: (无)
- user: "用一段话解释 RAG 的工作原理"
- expected_tokens: ~150

使用相同 prompt 便于与 A1（Qwen3.5 三平台）做横向对比。

## 平台 × 模型

| Provider | Model | Engine | 量化 |
|----------|-------|--------|------|
| ollama | gemma4:26b | **llama.cpp (Metal)** | Q4_K_M |
| omlx | gemma-4-26b-a4b-it-4bit | **MLX** | group-wise 4bit |

注意: 不测 mlx-lm。mlx-lm 和 oMLX 底层都是 MLX 框架，但 oMLX 有 SSD KV cache 等优化层，理论上可能存在差异。不加入的原因是：E1 的核心目标是展示 llama.cpp vs MLX 的引擎差距，加入 mlx-lm 会稀释这个对比焦点。如果 oMLX 与 mlx-lm 在 Gemma4 上有显著差异，可在后续 RUN 中单独验证

## 参数

- rounds: 10
- warmup: 1
- timeout: 180s（Gemma4 在 llama.cpp 上可能较慢）
- max_tokens: 512

## 核心指标

- TTFT (ms)
- decode tok/s: **本场景最关键指标** — llama.cpp vs MLX 的速度差
- 总耗时 (ms)
- 内存占用 (MB)

## 预期结果

- oMLX (MLX) 的 tok/s 应显著高于 Ollama (llama.cpp)
- 社区数据参考: MoE 模型 MLX vs llama.cpp 差距约 2-3x

## 已知限制

- 量化方式不同 (Q4_K_M vs group-wise 4bit)
- 引擎差异 + 量化差异不可拆分
- Gemma4-26B 是 MoE 架构（4B 激活参数），MoE 模型在 MLX 上优势更大
- 视频里需要说明: 这个差距不能简单推广到 Dense 模型
