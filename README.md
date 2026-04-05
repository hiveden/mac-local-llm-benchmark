# Mac Local LLM Benchmark

工具人研究所「本地大模型部署」系列的测评数据平台。

## 环境要求

- Mac (Apple Silicon, 32GB+ 统一内存)
- macOS Sequoia+
- Ollama 0.19+ (`brew install ollama`)
- oMLX (`brew install jundot/omlx/omlx`)
- mlx-lm (`pip3 install mlx-lm`)
- Python 3.11+

## 快速开始

```bash
# 运行测试
bash scripts/harness.sh runs/001-platform

# 分析结果
python3 scripts/analyze.py runs/001-platform
```

## 项目结构

- `scripts/` — 测试工具链（harness + provider 适配器 + 分析）
- `config/` — 全局配置（prompt 库 + 平台注册表）
- `runs/` — 每期测试的配置和结果
- `baselines.csv` — 跨期基线数据

详见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 测试边界

详见 [DISCLAIMER.md](DISCLAIMER.md)。

## 当前硬件

```
Mac Mini M4 Pro / 64GB Unified Memory / macOS Sequoia
```

## License

MIT
