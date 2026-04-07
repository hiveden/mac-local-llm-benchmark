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

每个测试场景完全独立、自包含。直接进入场景目录运行 `run.sh`：

```bash
# 跑单个场景的全部 provider
cd runs/001-platform/scenarios/A1-single-short
bash run.sh

# 只跑指定 provider
bash run.sh ollama

# 列出可用 provider
bash run.sh --list
```

分析数据（支持场景级或 RUN 级）：

```bash
# 单场景分析
python3 scripts/analyze.py runs/001-platform/scenarios/A1-single-short

# 整期汇总分析（自动扫描所有场景）
python3 scripts/analyze.py runs/001-platform
```

## 项目结构

- `scripts/` — 共享工具：`analyze.py`（数据分析与报告）+ `sysinfo.sh`（环境采集）
- `runs/NNN-xxx/scenarios/` — 每期下若干自包含场景，每个场景都有自己的 `DESIGN.md` / `config.json` / `run.sh` / `data/` / `results/`
- `config/` — 早期参考模板（providers/prompts），**不被任何场景使用**，仅供新建场景时复制
- `baselines.csv` — 跨期基线数据
- `DISCLAIMER.md` — 测试边界声明（所有 RUN 继承）

完整架构和设计原则详见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 当前硬件

```
Mac Mini M4 Pro / 64GB Unified Memory / macOS Sequoia
```

## License

MIT
