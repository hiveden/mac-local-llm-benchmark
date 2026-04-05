# E2: Gemma4-26B 跨引擎长 prompt 对比

## 目的

与 E1 互补：E1 用短 prompt 测 decode 速度差距，E2 用长 prompt（~2300 字 Transformer 技术文档）测 prefill 性能差距。

长 prompt 场景下，prefill 阶段占总延迟的比例显著增大。不同引擎（llama.cpp vs MLX）在 prefill 上的效率差异会直接反映在 TTFT 上。这是 E1 短 prompt 无法充分展示的维度。

## 背景

同 E1：Gemma4 在 Ollama 走 llama.cpp (Metal)，在 oMLX 走 MLX 原生。
Prompt 与 A3 完全相同（同一篇 Transformer 技术文档，~2300 字），有意为之——控制变量，只换模型和引擎，使 E2 和 A3 的数据可交叉对比。

## 前置条件

- thinking: false
- 测试前卸载所有平台模型，从冷启动开始

## Prompt

- system: (无)
- user: A3 的 Transformer 架构技术文档 + "请用 200 字总结以上内容的核心要点"
- expected_tokens: ~200

## 平台 x 模型

| Provider | Model | Engine | 量化 |
|----------|-------|--------|------|
| ollama | gemma4:26b | **llama.cpp (Metal)** | Q4_K_M |
| omlx | gemma-4-26b-a4b-it-4bit | **MLX** | group-wise 4bit |

## 参数

- rounds: 10
- warmup: 1
- timeout: 180s
- max_tokens: 512

## 核心指标

- **TTFT (ms)**: 本场景最关键指标 -- 长 prompt prefill 效率差距
- decode tok/s
- 总耗时 (ms)
- 内存占用 (MB)

## 与 E1 的对比价值

| 维度 | E1 (短 prompt) | E2 (长 prompt) |
|------|----------------|----------------|
| Prompt 长度 | ~20 字 | ~2300 字 |
| 测试重点 | decode 速度 | prefill 效率 |
| TTFT 占比 | 低 | 高 |
| 预期差距 | tok/s 差距明显 | TTFT 差距更明显 |

## 预期结果

- oMLX (MLX) 的 TTFT 应显著低于 Ollama (llama.cpp)，差距比 E1 更大
- decode tok/s 差距应与 E1 类似（decode 阶段与 prompt 长度无关）

## 已知限制

- 同 E1：量化方式不同，引擎差异 + 量化差异不可拆分
- Gemma4-26B 是 MoE 架构，结论不能简单推广到 Dense 模型
