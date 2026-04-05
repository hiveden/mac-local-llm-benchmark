# 设计决策记录

> 记录代码审核中发现的问题和取舍决策，避免重复讨论。

## 已知限制（设计选择，不改）

### 1. Shell 变量直接插入 Python 字符串

`lib.sh` 多处用 `'$RUN_DIR/sysinfo.json'` 等方式把路径传给内嵌 Python，违反 CLAUDE.md "用环境变量传参"的约定。

**不改的原因**: 路径来源全部可控（config.json 里的值、脚本内部计算的路径），不存在用户输入注入。改的话涉及 lib.sh 20+ 处，收益低风险也低。如果未来路径包含特殊字符（单引号等），需要回来改。

### 2. FREE_MEM 只取 vm_stat Pages free

macOS 积极使用内存做缓存，`Pages free` 通常只有几百 MB，不代表真正可用内存。

**不改的原因**: FREE_MEM 只是 `_env_baseline.json` 里的参考记录，不参与测评指标计算。加 inactive/purgeable 页会让逻辑复杂化。如果需要精确内存数据，应该用 `memory_pressure` 命令，但那是另一个工具的事。

### 3. Ollama get_memory 用 awk 遍历找 GB/MB

`ollama ps` 输出格式不固定，遍历所有字段找 "GB"/"MB" 有误匹配风险（如模型名包含这些字符串）。

**不改的原因**: 当前模型名（qwen3.5:35b-a3b-nvfp4, gemma4:26b）不包含 GB/MB。`ollama ps --format json` 在 0.20.2 上未确认是否支持，贸然改可能引入新问题。

### 4. oMLX/mlx-lm 内存用 ps RSS 不准确

Apple Silicon 统一内存下，`ps -o rss` 不反映真实 GPU 内存占用。

**不改的原因**: oMLX 没有像 `ollama ps` 那样的 VRAM 查询接口。ps RSS 是目前唯一的通用方案。在 `my-take.md` 和视频中需要说明这个局限性。Ollama 的内存数据（ollama ps VRAM）是准确的。

### 5. Token 估算 fallback 对中文偏差大

`len(content) // 2` 按英文估算（~2 chars/token），中文应该是 ~1-1.5 token/字符。

**不改的原因**: 只在 API 不返回 token 计数时触发（正常不会）。已通过 `token_source: "estimated"` 标记，analyze.py 会输出警告。三个平台正常情况都返回准确的 token 计数。

### 6. TTFT 测量包含 Python 解释器开销

`start_time = time.time()` 在 Python 脚本入口设置，但 curl 请求在此之前已通过管道启动。TTFT 实际测的是"Python 开始读 stdin 到首 token 到达"，不含网络连接建立时间。

**不改的原因**: 三个平台都走 localhost，都有相同的系统偏差。相对差异是准的，对比结论不受影响。绝对值会偏低约 5-10ms。如果需要精确 TTFT，应该用 Python 直接发 HTTP 请求（不经管道），但那需要重写整个请求逻辑。

### 7. prompt_id 字段未写入 metrics JSON

analyze.py 按 `(test_name, provider, prompt_id)` 分组，但 JSON 里没有 prompt_id。当前每场景一个 prompt，分组不受影响（prompt_id 为空字符串）。

**不改的原因**: 当前架构是每场景一个 prompt，prompt_id 冗余。如果未来改为多 prompt 场景，需要在 lib.sh 的 send_request 中加入 prompt_id 写入。

### 8. A1/A2/A3/E1 的 run.sh 完全相同

四个文件逐行一致，改通用逻辑要改 4 个文件。

**不改的原因**: 场景数量少（4 个）。合成一个 `run-single.sh` 会破坏"一个场景一个目录"的独立性。lib.sh 已经承担了代码复用职责，run.sh 只是薄壳。如果未来场景超过 10 个，可以考虑提取。

### 9. config/ 全局配置文件未被使用

`config/providers.json` 和 `config/prompts.json` 是最初架构设计的产物，现在每个场景的 config.json 内联了所有配置。

**处理方式**: 删掉或加说明。场景独立性比配置 DRY 更重要——改全局配置不应该影响已跑完的场景数据。

### 10. || true 过度使用

oMLX login、model unload、cache query 等多处错误被静默吞掉。

**不改的原因**: 清理和监控操作失败不应该阻塞测试本身。缓存状态会被 `get_cache_info` 记录到 metrics JSON，分析时可以检查。如果需要调试清理问题，临时去掉 `|| true` 即可。

### 11. E1 传 --provider mlx-lm 静默跳过

E1 只有 2 个 provider（ollama + omlx），传不存在的 provider 名不会报错，只是跳过。

**不改的原因**: `--list` 已列出可用 provider，用户可以自行确认。加错误提示会增加逻辑复杂度，收益低。

### 12. B1 轮间清理不包含 mlx-lm

mlx-lm 没有 session 级 KV cache 持久化，每次请求独立计算。

**不改的原因**: mlx-lm server 0.31.1 确认无跨请求缓存。如果未来版本加了缓存特性，需要回来改。

### 13. oMLX cookie 文件竞态

cleanup_environment 的 cookie 写到固定路径 `/tmp/omlx-bench-cookies.txt`，并行跑两个场景会冲突。

**不改的原因**: 测试必须串行执行（避免内存竞争），不存在并行场景。
