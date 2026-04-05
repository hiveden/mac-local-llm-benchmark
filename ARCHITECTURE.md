# Mac Local LLM Benchmark — 项目架构

> 工具人研究所「本地大模型部署」系列的数据基座
> 所有模型部署相关选题的测评、数据、分析都在这里

## 定位

持续运营的基准测试平台：
- RUN 01（Ollama vs oMLX vs mlx-lm）是第一期
- 新工具、新模型、新量化方式出现时，新增场景跑对比数据
- 数据开源，观众可复现

## 硬件基线

```
Machine: Mac Mini M4 Pro / 64GB Unified Memory / macOS Sequoia
固定不变 — 所有数据基于同一台机器，可比性有保障
```

## 项目结构

```
mac-local-llm-benchmark/
├── README.md                      # 项目介绍、快速开始、环境要求
├── ARCHITECTURE.md                # 本文件
├── CLAUDE.md                      # 项目原则和技术约定
├── DISCLAIMER.md                  # 测试边界声明（所有 RUN 继承）
├── CHANGELOG.md                   # 每次新增 RUN 记录
├── baselines.csv                  # 从各期提取的关键指标（持续增长的资产）
│
├── scripts/                       # 共享工具（分析、系统信息）
│   ├── analyze.py                 # 数据分析 + 图表 + 报告生成
│   └── sysinfo.sh                 # 硬件/软件环境自动采集（备用）
│
├── runs/                          # 每期一个目录
│   └── 001-platform/              # RUN 01: 三平台对比
│       ├── README.md              # 本期总览 + 场景设计取舍
│       ├── sysinfo.json           # 环境快照（首次运行时自动采集）
│       ├── scenarios/             # 每个场景完全独立
│       │   ├── A1-single-short/   # 短问答
│       │   │   ├── DESIGN.md      # 测试设计文档
│       │   │   ├── config.json    # 场景参数（providers, prompt, rounds）
│       │   │   ├── run.sh         # 自包含测试脚本
│       │   │   ├── data/          # 原始数据（每轮一个 JSON）
│       │   │   └── results/       # 分析结果
│       │   ├── A2-single-code/    # 代码生成
│       │   ├── A3-single-long/    # 长文本总结
│       │   ├── B1-multi-turn/     # 多轮对话（缓存命中）
│       │   └── E1-gemma4-cross/   # Gemma4 跨引擎
│       ├── results/               # 跨场景汇总
│       └── my-take.md             # 个人观点
│
├── archive/                       # 归档（.gitignore）
│
└── docs/                          # 频道相关（不开源）
    └── run-01/
        └── brief-03-plan.md       # 需求文档存档
```

## 核心设计原则

### 1. 场景完全独立

每个场景（A1/A2/B1 等）是一个自包含目录：
- `DESIGN.md` — 为什么测、怎么测、预期
- `config.json` — 所有参数（providers, prompt, rounds）
- `run.sh` — 自包含脚本，不依赖外部文件
- `data/` — 原始数据
- `results/` — 分析结果

新增场景不影响已有场景。已跑完的数据不被后续修改污染。

运行方式：
```bash
cd runs/001-platform/scenarios/A1-single-short
bash run.sh              # 跑全部 provider
bash run.sh ollama       # 只跑指定 provider
bash run.sh --list       # 列出可用 provider
```

### 2. 每个 provider 的差异内聚在 run.sh 中

三个平台关闭 thinking、流式 API 格式、内存采集方式都不同：

| | Ollama | oMLX | mlx-lm |
|--|--------|------|--------|
| 关闭 thinking | `/api/chat` + `think: false` | `chat_template_kwargs` | `--chat-template-args` 启动参数 |
| 流式格式 | NDJSON（私有 API） | SSE（OpenAI 兼容） | SSE（OpenAI 兼容） |
| 内存采集 | `ollama ps` VRAM | ps RSS | ps RSS |

这些差异全部内聚在 run.sh 的 `send_request` 函数中，按 provider_name 分支处理。

### 3. 标准指标体系

每轮请求产出一个 JSON：

```json
{
  "provider": "ollama",
  "model": "qwen3.5:35b-a3b-nvfp4",
  "prompt_tokens": 12,
  "tokens_generated": 98,
  "total_time_ms": 1702,
  "ttft_ms": 200,
  "decode_tok_s": 65.26,
  "memory_before_mb": 21504,
  "memory_after_mb": 21504,
  "response": "...",
  "reasoning": null,
  "round": 1,
  "is_warmup": true,
  "cache": { "type": "kv-cache-snapshot", "model_in_memory": true }
}
```

内存测量策略（Apple Silicon 统一内存下 RSS 不准确）：
```
Ollama:  ollama ps → VRAM Size（最准确）
oMLX:    ps RSS（降级方案）
mlx-lm:  ps RSS（单进程 Python，相对准确）
```

### 4. 数据可追溯

- 所有 data/ 进 git，任意 commit 可回退复现
- 每个 provider 测试前记录 `_env_baseline.json`（空闲内存、时间戳）
- 每轮记录缓存状态
- 环境清理确保干净初始状态

### 5. 断点续跑

- 已完成的 provider（数据条数 >= rounds）自动跳过
- 已存在的轮次自动跳过
- Ctrl+C 后重新跑同一命令安全接续
- 重跑某个 provider：`rm -rf data/provider_name/`

## 数据生命周期

```
1. 写 DESIGN.md → commit "A1: 测试设计"
2. 写 run.sh + config.json → commit "A1: 测试脚本"
3. 跑测试 → commit "A1: 原始数据"
4. 分析 → commit "A1: 分析结果"
5. 提取关键指标追加到 baselines.csv
6. git tag run-001
```

baselines.csv 是项目持续增长的核心资产，后续新工具出来直接对比历史数据。

## 扩展路线

| RUN | 选题 | 对比维度 |
|-----|------|---------|
| 001 | 三平台对比 | Ollama vs oMLX vs mlx-lm |
| 002 | 量化方式 | NVFP4 vs Q4_K_M vs group-4bit |
| 003 | 并发吞吐 | 单请求 vs 2/4/8 并发 |
| 004 | 长上下文 | 4K vs 8K vs 16K vs 32K |
| 005 | 模型横评 | Qwen vs Gemma vs Llama 同级别 |
| 006 | 冷启动 | 首次加载 vs 热加载 vs SSD cache |
| 007 | 稳定性 | 4 小时连续运行衰减曲线 |
| 008 | 中英文 | 同 prompt 中英文性能差异 |

## 技术栈

- 测试脚本: Bash + Python（确定性，不用 LLM）
- 数据分析: Python (pandas + matplotlib)
- 图表: matplotlib → PNG
- 报告: Python → Markdown
- 版本控制: Git（每个场景独立 commit，每期打 tag）
