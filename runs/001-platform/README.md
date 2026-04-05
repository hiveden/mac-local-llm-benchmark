# RUN 01: Ollama vs oMLX vs mlx-lm 三平台对比

> 工具人研究所 RUN 系列第一期
> 日期: 2026-04-05
> 硬件: Mac Mini M4 Pro / 64GB / macOS Sequoia

## 背景

Brief 02 翻车点:
- 结论"Ollama 0.19 MLX 是 Mac 本地最佳方案"过于绝对
- 大部分模型实际跑的是 GGUF+Metal，不是 MLX
- 漏掉 oMLX 方案
- 评论区大量质疑

## 目标

从"性能评测"转向"对评论区质疑的正式回应 + 选型方法论"。
- 轨道一: 本地跑测试 → 输出数据 → 开源（客观、可复现）
- 轨道二: 基于数据的个人观点（主观、明确适用边界）

## 测试场景

| 场景 | 设计文档 | 平台 | 测什么 |
|------|---------|------|--------|
| A1 短问答 | [DESIGN.md](scenarios/A1-single-short/DESIGN.md) | Ollama / oMLX / mlx-lm | TTFT + 短文本速度 |
| A2 代码生成 | [DESIGN.md](scenarios/A2-single-code/DESIGN.md) | Ollama / oMLX / mlx-lm | 中等长度生成 |
| A3 长文本总结 | [DESIGN.md](scenarios/A3-single-long/DESIGN.md) | Ollama / oMLX / mlx-lm | 长 prompt prefill |
| B1 多轮对话 | [DESIGN.md](scenarios/B1-multi-turn/DESIGN.md) | Ollama / oMLX / mlx-lm | 缓存命中对 TTFT 的影响 |
| E1 Gemma4 跨引擎 | [DESIGN.md](scenarios/E1-gemma4-cross/DESIGN.md) | Ollama / oMLX | llama.cpp vs MLX 差距 |
| E2 Gemma4 长 prompt | [DESIGN.md](scenarios/E2-gemma4-long/DESIGN.md) | Ollama / oMLX | 长 prompt prefill 效率差距 |

## 场景设计取舍

### 为什么是这 5 个场景

RUN 01 的主题是**平台对比**（Ollama vs oMLX vs mlx-lm），不是模型评测或功能覆盖。场景选择的原则是：用最少的变量覆盖三个平台的核心差异。

- **A1/A2/A3 单轮请求**: 控制变量（同模型、同 prompt、不同平台），测裸速差异。三个 prompt 覆盖短/中/长三种输入长度，确保结论不依赖特定 prompt 类型
- **B1 多轮对话**: oMLX 的核心差异化能力是 SSD KV cache，单轮请求测不出来。这个场景专门验证缓存命中对 TTFT 的影响
- **E1 Gemma4 跨引擎**: 直接回应评论区"Ollama MLX 是否对所有模型生效"的质疑。Gemma4 在 Ollama 走 llama.cpp，在 oMLX 走 MLX，是展示引擎差距最直观的对比

### 为什么不测以下场景

| 场景 | 不测的原因 | 计划 |
|------|-----------|------|
| Thinking 模式开/关 | 模型行为差异，不是平台差异。且三个平台对 thinking 的实现不同，数据不可比 | RUN 02 |
| 并发吞吐 | 有价值但增加复杂度，RUN 01 先建立单请求基线 | RUN 03 |
| 冷启动 vs 热启动 | warmup 轮已包含冷启动数据，可从现有数据分析 | 从 A1 数据中提取 |
| 长时间稳定性 | 需要 4 小时+连续运行，超出本期范围 | RUN 04 |
| 中英文差异 | 有价值但会让场景翻倍，本期优先控制变量数量 | RUN 05 |
| E1 中加 mlx-lm | mlx-lm 和 oMLX 用同一个 MLX 框架，结果会高度相似，信息增量低 | 不计划 |

### 为什么关闭 Thinking

Qwen3.5 默认开启 thinking 模式。关闭的原因：
1. 测试目标是平台速度，不是模型推理能力
2. 三个平台对 thinking 输出的字段不同（Ollama 用 reasoning，其他可能用 content），tok/s 统计口径不一致
3. 用户实际日常使用是关闭 thinking 的

## 全局设置

- thinking: false（测纯回答速度）
- 每场景 10 轮，1 轮预热
- 每个 provider 测试前清理环境（卸载所有模型，等待内存释放）

## 设计决策

代码审核中发现的已知限制和取舍决策，见 [DECISIONS.md](DECISIONS.md)。

## 已知问题

测试过程中发现的数据问题和注意事项，见 [KNOWN_ISSUES.md](KNOWN_ISSUES.md)。
关键：oMLX/mlx-lm 的 tok/s 为估算值（不可信），TTFT 和总耗时精确可信。

### warmup 策略

每场景 1 轮 warmup（round_01 标记为 `is_warmup: true`，analyze 时过滤）。warmup 的目的是完成模型加载和首次推理的初始化开销，而非消除所有波动。如果 round_02 与 round_03+ 仍有显著差异，说明 1 轮 warmup 不够，可在分析阶段追加过滤。

### 内存采集口径

三个平台的内存采集方式不同，**数值不可直接横向比较**：

| Platform | 采集方式 | 含义 |
|----------|---------|------|
| Ollama | `ollama ps` Size 字段 | 模型 VRAM 占用（准确反映模型大小） |
| oMLX | `ps RSS` | 进程常驻内存（含 Python runtime + MLX 框架开销） |
| mlx-lm | `ps RSS` | 进程常驻内存（含 Python runtime + MLX 框架开销） |

内存数据仅作辅助参考，核心对比指标是 TTFT 和 tok/s。

## 原始需求文档

见 docs/run-01/brief-03-plan.md
