# 测试边界声明

## 这份数据能回答

- 三个工具在 M4 Pro 64GB + 这些模型 + 这些任务的性能差异

## 这份数据不能回答

- 其他 Mac 配置（M1/M2/M3/M5, 8GB/16GB/32GB/128GB）的表现
- 其他模型（Llama/DeepSeek/Mistral 等）的表现
- 长时间（4 小时+）连续运行的稳定性
- 量化精度对输出质量的影响（需人工评估）
- 中文 vs 英文任务差异
- 多用户并发场景

## 量化差异陷阱

三个工具跑的不是同一份量化文件：
- Ollama: NVFP4 量化（Ollama 自有格式）
- oMLX / mlx-lm: mlx-community group-wise 4bit 量化（HuggingFace 社区格式）

速度差异 = 工具封装层差异 + 量化算法差异，两者不可拆分。

## 复现方法

见 README.md 的环境要求和运行步骤。
