# My Take — RUN 01 个人观点

> 基于 RUN 01 数据的个人判断，带有主观性。
> 数据见 results/summary.md，审计见 KNOWN_ISSUES.md。

## 六条结论

### 1. TTFT（首 token 延迟）：oMLX 最快，但差距在百毫秒级

- 短 prompt：oMLX 87ms < Ollama 133ms < mlx-lm 204ms
- 长 prompt：oMLX 1317ms < Ollama 1455ms < mlx-lm 1619ms
- 实际使用中，短 prompt 场景差距不到 120ms，用户几乎感知不到

### 2. 总耗时：mlx-lm 端到端最短

- A1 短问答：mlx-lm 1293ms < Ollama 1662ms < oMLX 1795ms
- A2 代码生成：mlx-lm 11710ms < Ollama 15699ms < oMLX 16109ms
- A3 长文本总结：mlx-lm 3025ms < oMLX 3078ms < Ollama 3282ms
- 但生成 token 数未精确测量（oMLX/mlx-lm 流式不返回 completion_tokens），无法区分是 decode 更快还是输出更短

### 3. Gemma4 跨引擎：MLX vs llama.cpp 差距显著（长 prompt 场景）

- E2 长 prompt prefill：oMLX (MLX) 408ms vs Ollama (llama.cpp) 2655ms，**6.5x**
- E2 总耗时：oMLX 3740ms vs Ollama 7659ms，**2.0x**（decode 阶段稀释了 prefill 优势）
- E1 短 prompt 总耗时：oMLX 1706ms vs Ollama 2512ms，1.5x
- RAG / 长文档等长输入场景，MLX 后端收益明确

### 4. Qwen3.5 三个 backend 的 prefill 吞吐接近

- A1→A3 prefill 增量：Ollama 1322ms、oMLX 1230ms、mlx-lm 1415ms（差距 <15%）
- Qwen3.5 场景下 Ollama 走 MLX 引擎（0.19+ nvfp4），三个平台底层引擎相同
- 绝对 TTFT 的差异来自各 backend 的固定启动开销，不是 prefill 吞吐本身
- 注意：这和结论 3 不矛盾——结论 3 是 Gemma4 上 MLX vs llama.cpp（不同引擎），本条是 Qwen3.5 上三个 MLX backend（同引擎）

### 5. 缓存是 benchmark 最大陷阱

- Ollama 的 KV cache 命中让 A3 TTFT 显示为真实值的 1/25（58ms vs 1455ms）
- mlx-lm 的 prompt cache 让 A1 TTFT 显示为真实值的 1/9（172ms vs 1573ms）
- 这不是平台的 bug——KV cache 和 prompt cache 都是合理的性能优化设计
- 但如果 benchmark 不清缓存，跑出来的 TTFT 数据完全不反映真实 prefill 性能
- 我们跑了 4 轮才拿到干净数据，每轮发现一个新的缓存问题

### 6. tok/s 在流式模式下只有 Ollama 可信

- oMLX/mlx-lm 的 SSE 流式响应不返回 completion_tokens
- 代码 fallback 到字符数估算（len//2），实测偏差可达 50%
- Ollama tok/s：~66 tok/s (Qwen3.5 35B)，~47 tok/s (Gemma4 26B)
- oMLX/mlx-lm 的 tok/s 需要非流式场景（T1）独立补充

## 未解之谜

**为什么 Gemma4 上 MLX vs llama.cpp 差 6.5x，而 Qwen3.5 上三个 MLX backend 差距 <15%？**

可能的解释：
- Ollama 对 Qwen3.5 走 MLX（nvfp4），对 Gemma4 走 llama.cpp——不是同一个引擎
- llama.cpp 对 Gemma4 的 MoE 架构可能有特定瓶颈
- 也可能是量化方式差异（Q4_K_M vs group-4bit）

这个不一致性值得在下一期深入。

## 选型建议

| 用户画像 | 推荐 | 理由 |
|---------|------|------|
| 日常使用不想折腾 | **Ollama** | 生态最全，一键安装，TTFT 够快 |
| 追求最低 TTFT | **oMLX** | 所有场景 TTFT 最快，但需要手动管理模型 |
| 追求最短总耗时 | **mlx-lm** | decode 最快，但需要手动启停 server |
| Gemma4 等非 Qwen 模型 | **oMLX** | Ollama 走 llama.cpp 慢 2-6.5x |
| 做 benchmark | **三个都装** | 不同平台测的是不同东西，需要对比视角 |

一句话：**90% 的 Mac 用户用 Ollama 就够了。追求极致再看 oMLX/mlx-lm。**

## 这次测评本身的教训

1. **缓存是最大的坑**——不调研平台缓存机制就跑 benchmark，数据白跑
2. **流式 API 不返回 token 数**——tok/s 这个最直观的指标反而最难准确测量
3. **Bash 写测试脚本是错误的选型**——RUN 02 改纯 Python
4. **小步验证优于一次性全量**——先手动跑两次确认行为，再写自动化脚本

详见 [RETRO.md](RETRO.md)。
