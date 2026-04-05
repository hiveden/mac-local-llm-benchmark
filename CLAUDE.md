# CLAUDE.md

## 项目原则

### 测试过程中不改代码
用户在跑测试时，绝对不能修改任何脚本或配置文件。所有修改必须在测试前完成并确认。

### 场景独立性
每个测试场景（A1/A2/B1 等）是完全自包含的，互不依赖。新增场景不能影响已有场景的数据和脚本。已跑完的场景数据不可被后续修改污染。

### 先测试后交付
脚本写完后必须自己跑通验证，不能把用户当测试。交付给用户的脚本必须是验证通过的。

### 数据可追溯
所有测试数据（data/）进 git。每次测试前后的环境状态（sysinfo、缓存、内存基线）都要记录。任意 commit 都应该能回退并复现当时的测试结果。

### 配置驱动
脚本不硬编码 URL、端口、API key、模型名。所有可变参数从配置文件读取。

### 环境隔离
每个 provider 测试前必须清理环境（卸载所有模型、释放内存），记录清理后的内存基线，确保干净的初始状态。

## 技术约定

### 语言
- 文档和注释用中文
- 代码标识符和技术术语保持英文

### 脚本语言选型
- **新脚本优先用纯 Python**（httpx 调 API、JSON 处理、统计计算，一个语言内闭环）
- Bash 只在真正需要 shell 能力时使用（系统命令编排、进程管理等）
- 不用 Bash + 内嵌 Python 混合方式（变量注入脆弱、调试困难、引号地狱）
- RUN 01 的 lib.sh/run.sh 是 Bash 实现（历史原因），RUN 02 起改为纯 Python

### 现有 Bash 脚本约定（RUN 01）
- `set -euo pipefail` 严格模式，外部命令加 `|| true` 防止误退出
- 用数组 `curl_args+=()` 构造 curl 参数，不用 eval 拼接字符串
- 用环境变量传参给内嵌 Python，不用 shell 变量直接插入 Python 字符串

### Git 工作流
每个场景的生命周期:
1. DESIGN.md → commit
2. run.sh → commit
3. 跑测试 → data/ commit
4. 分析 → results/ commit

### 平台 API
- providers.json 中 base_url 已包含 `/v1`，脚本中不要重复拼接
- Ollama 内存用 `ollama ps`（VRAM），不用 `ps -o rss`
- 流式请求同时采集 `delta.content` 和 `delta.reasoning`（thinking 模型兼容）
