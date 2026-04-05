# My Take — RUN 01 个人观点

> 基于 RUN 01 数据的个人判断，带有主观性。适用范围：M4 Pro 64GB + 以下模型 + 2026 年 4 月。
> 数据见 results/summary.md，审计见 KNOWN_ISSUES.md。

## 六条结论

### 1. TTFT（首 token 延迟）：oMLX 最快，差距在百毫秒级

- 短 prompt：oMLX 87ms < Ollama 133ms < mlx-lm 204ms
- 长 prompt：oMLX 1317ms < Ollama 1455ms < mlx-lm 1619ms
- 短 prompt 场景三平台差距 120ms 以内，长 prompt 场景差距约 300ms

### 2. 总耗时：mlx-lm 端到端最短

- A1 短问答：mlx-lm 1293ms < Ollama 1662ms < oMLX 1795ms
- A2 代码生成：mlx-lm 11710ms < Ollama 15699ms < oMLX 16109ms
- A3 长文本总结：mlx-lm 3025ms < oMLX 3078ms < Ollama 3282ms
- T1 非流式补充数据（A1 prompt）确认 mlx-lm decode 速度最快：78 tok/s > Ollama 63 tok/s > oMLX 60 tok/s
- 但 T1 仅覆盖 A1 短 prompt，A2/A3 的精确 token 数未测量，不能排除"不同场景下输出长度不同"对总耗时的影响

### 3. Gemma4 跨引擎：MLX vs llama.cpp 差距显著（长 prompt 场景）

- E2 长 prompt prefill：oMLX (MLX) 408ms vs Ollama (llama.cpp) 2655ms，**6.5x**
- E2 总耗时：oMLX 3740ms vs Ollama 7659ms，**2.0x**（decode 阶段稀释了 prefill 优势）
- E1 短 prompt 总耗时：oMLX 1706ms vs Ollama 2512ms，1.5x
- RAG / 长文档等长输入场景，MLX 后端收益明确
- **注意时效性**：此结论基于 Ollama 0.20.2 对 Gemma4 走 llama.cpp 的现状。Gemma4 MLX 支持 [已在开发中](https://github.com/ollama/ollama/pull/15244)，未来 Ollama 加上后这个差距会消失

### 4. Qwen3.5 三个 backend 的 prefill 吞吐接近

- A1→A3 prefill 增量：Ollama 1322ms、oMLX 1230ms、mlx-lm 1415ms（差距 <15%）
- Qwen3.5 场景下 Ollama 走 MLX 引擎（0.19+ nvfp4），三个平台底层引擎相同
- 三个 backend 的纯 prefill 增量差距 <15%，但 A1 TTFT 差距达 2.3x（87ms vs 204ms）。这个差距的具体来源未进一步分析：

| Provider | A1 TTFT | A3-A1（≈纯 prefill 增量） |
|----------|---------|-------------------------|
| oMLX | **87ms** | 1230ms |
| Ollama | 133ms | 1322ms |
| mlx-lm | 204ms | 1415ms |

- A1 TTFT 差 2.3x（87 vs 204ms），纯 prefill 增量差 <15%
- 注意：这和结论 3 不矛盾——结论 3 是 Gemma4 上 MLX vs llama.cpp（不同引擎），本条是 Qwen3.5 上三个 MLX backend（同引擎）

### 5. 缓存是 benchmark 最大陷阱

- Ollama 的 KV cache 命中让 A3 TTFT 显示为真实值的 1/25（58ms vs 1455ms）
- mlx-lm 的 prompt cache 命中让 A1 TTFT 显示为真实值的 1/9（172ms vs 1573ms）
- 这不是平台的 bug——KV cache 和 prompt cache 都是合理的性能优化设计，正常使用时能显著提升体验
- 但 benchmark 场景下如果不清缓存，TTFT 数据不反映真实 prefill 性能，会误导跨平台对比
- 我们跑了 4 轮才拿到干净数据，每轮发现一个新的缓存问题

### 6. tok/s：T1 非流式数据补充

- oMLX/mlx-lm 流式不返回 completion_tokens，流式 tok/s 不可信
- T1 非流式精确数据（A1 短 prompt）：

| Provider | Tokens (median) | 非流式总耗时 | tok/s |
|----------|----------------|-------------|-------|
| mlx-lm | 100 | 1277ms | **78.1** |
| ollama | 100 | 1602ms | **62.5** |
| omlx | 118 | 1959ms | **60.2** |

- 仅限 A1 prompt，A2/A3 未精确测量

## Ollama MLX 加速的技术实现

**Ollama 的 MLX 加速是按架构逐个实现的**，每个架构需要独立用 Go 实现 forward pass 并调用 MLX C++ bindings。证据：

- 官方博客原话："We will **expand the list of supported architectures**."（[ollama.com/blog/mlx](https://ollama.com/blog/mlx)）
- 源码结构：每个架构是独立的 Go 包（[`x/models/qwen3/`](https://github.com/ollama/ollama/tree/main/x/models/qwen3)、[`x/models/glm4_moe_lite/`](https://github.com/ollama/ollama/tree/main/x/models/glm4_moe_lite) 等），各自实现 Forward 方法
- MLX runner 作为子进程运行（[`x/mlxrunner/`](https://github.com/ollama/ollama/tree/main/x/mlxrunner)），通过 HTTP 与主服务通信
- Go bindings 封装 MLX C++ API（[DeepWiki 文档](https://deepwiki.com/ollama/ollama/5.7-mlx-runner-(apple-silicon))："The MLX runner uses a registry-based system to instantiate different transformer architectures"）

截至 2026.04 只有 Qwen3.5 系列提供了 [8 个 nvfp4 版本](https://ollama.com/library/qwen3.5/tags)。Gemma4 MLX 支持 [正在开发](https://github.com/ollama/ollama/pull/15244)（Draft PR #15244），但尚未合并。

这意味着 **Ollama MLX 加速的覆盖面受限于团队的实现进度**，而 oMLX 直接使用 Python MLX 生态，对 HuggingFace mlx-community 的模型即装即用。

## 两个平台的发展阶段不同

对比 oMLX 和 Ollama 最近的版本日志：

**oMLX**（0.2.x → 0.3.x）：密集修复 crash、内存泄漏、Metal buffer 竞争条件、内核 panic 等稳定性相关 bug。上期有博主测 oMLX 27B 崩溃的报告，最近 0.2.x 版本修了一批内存和 Metal 相关的 crash，是否覆盖了该场景未单独验证。本次测试 0.3.2 跑 Qwen3.5 35B + Gemma4 26B 共 70 次请求零故障，但长时间运行稳定性未验证。

**Ollama**（0.19 → 0.20.x）：引入 MLX 引擎、新增 Gemma4 模型支持、优化 flash attention、改进 KV cache。处于功能扩展和性能优化阶段。

从版本日志看，**oMLX 最近几个版本仍在修复稳定性相关的 bug，Ollama 已经在做功能迭代**。

## 选型建议（2026 年 4 月快照）

### Mac 本地日常稳定使用：Ollama

- 生态最全，一键安装，社区最大
- Qwen3.5 已有 MLX 加速（nvfp4），性能和 oMLX 差距 <10%
- KV cache / 模型管理等开箱即用

### 想要更多选择和更快的新模型支持：oMLX

- 原生 MLX，对所有 MLX 格式模型即装即用
- 不需要等 Ollama 出 nvfp4 量化版
- Gemma4 等新模型可以第一时间体验
- 代价：最近几个版本仍在修复稳定性 bug，需要手动管理模型
- 适合愿意折腾、追求最新的用户

### 想要 Gemma4 等非 Qwen 模型的 MLX 加速：oMLX（当前唯一选择）

- Ollama 对 Gemma4 走 llama.cpp，慢 2-6.5x
- **此结论有时效性**：Ollama Gemma4 MLX 支持正在开发，合并后差距会消失
- 如果只用 Qwen3.5，选 Ollama 和 oMLX 差别不大

### 做 benchmark / 追求裸跑基线：mlx-lm

- Apple MLX 团队维护的 Python 推理库（[github.com/ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm)），零封装开销
- T1 数据显示 A1 场景下 decode 最快（78 tok/s vs Ollama 63）
- 代价：手动启停 server，一次只能加载一个模型，无模型管理

### 一句话

**日常稳定用 Ollama，想折腾用 oMLX，做测评三个都装。**

## 这次测评本身的教训

1. **缓存是最大的坑**——不调研平台缓存机制就跑 benchmark，数据白跑
2. **流式 API 不返回 token 数**——tok/s 这个最直观的指标反而最难准确测量
3. **Bash 写测试脚本是错误的选型**——RUN 02 改纯 Python
4. **小步验证优于一次性全量**——先手动跑两次确认行为，再写自动化脚本

详见 [RETRO.md](RETRO.md)。
