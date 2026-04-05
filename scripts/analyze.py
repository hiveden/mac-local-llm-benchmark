#!/usr/bin/env python3
"""
analyze.py — 从 data/ 原始数据生成分析报告和图表

工作流程:
  1. 扫描 runs/NNN/data/ 下的所有 JSON 文件
  2. 过滤掉 warmup 轮次
  3. 按 (测试组, 平台, prompt) 分组
  4. 计算中位数、均值、标准差
  5. 输出 results/summary.md 和 results/raw.csv

用法:
  python3 scripts/analyze.py runs/001-platform

输入: runs/NNN/data/测试组/平台/prompt_roundN.json
输出: runs/NNN/results/summary.md + raw.csv
"""

import json
import os
import sys
import statistics
from pathlib import Path


def load_run_data(run_dir):
    """
    扫描测试数据，支持两种目录结构:

    场景级: run_dir/data/provider/round_*.json
      → 传入 runs/001-platform/scenarios/A1-single-short

    RUN 级: run_dir/scenarios/*/data/provider/round_*.json
      → 传入 runs/001-platform（自动扫描所有场景）
    """
    run_path = Path(run_dir)
    records = []

    # 判断是场景级还是 RUN 级
    scenarios_dir = run_path / "scenarios"
    if scenarios_dir.is_dir():
        # RUN 级: 扫描所有场景
        data_dirs = [(s.name, s / "data") for s in scenarios_dir.iterdir() if (s / "data").is_dir()]
    elif (run_path / "data").is_dir():
        # 场景级: 直接用 data/
        data_dirs = [(run_path.name, run_path / "data")]
    else:
        return records

    for scenario_name, data_dir in data_dirs:
        for metrics_file in data_dir.rglob("*.json"):
            if metrics_file.name in ("sysinfo.json", "_env_baseline.json"):
                continue
            try:
                with open(metrics_file) as f:
                    record = json.load(f)
                # 从路径提取 provider: data/ollama/round_01.json
                parts = metrics_file.relative_to(data_dir).parts
                record["test_name"] = scenario_name
                if len(parts) >= 2:
                    record["provider"] = parts[0]
                records.append(record)
            except (json.JSONDecodeError, KeyError) as e:
                print(f"WARNING: 跳过 {metrics_file}: {e}", file=sys.stderr)

    return records


def analyze(records):
    """
    按 (测试组, 平台, prompt) 分组，计算统计指标

    关键指标:
      - decode_tok_s: 解码速度（token/秒），越高越好
      - total_ms: 总耗时（毫秒），越低越好
      - stdev: 标准差，衡量稳定性，越低越好
    """
    # 过滤掉 warmup 轮次（warmup 数据只用于预热，不参与统计）
    valid = [r for r in records if not r.get("is_warmup", False)]

    # 常规分组: 排除 B1 多轮数据（有 turn 字段），B1 在多轮分组中单独处理
    single_turn = [r for r in valid if "turn" not in r]
    groups = {}
    for r in single_turn:
        key = (r.get("test_name", ""), r.get("provider", ""), r.get("prompt_id", ""))
        groups.setdefault(key, []).append(r)

    # 检查是否存在估算 token 数据
    has_estimated_tokens = any(r.get("token_source") == "estimated" for r in valid)

    results = []
    for (test, provider, prompt), group in sorted(groups.items()):
        ttft_list = [r["ttft_ms"] for r in group if r.get("ttft_ms", 0) > 0]
        total_ms_list = [r["total_time_ms"] for r in group if r.get("total_time_ms", 0) > 0]
        mem_list = [r["memory_after_mb"] for r in group if r.get("memory_after_mb", 0) > 0]

        if not ttft_list:
            continue

        # token 相关指标: 只用 token_source=api 的数据，estimated 不参与统计
        api_records = [r for r in group if r.get("token_source") == "api"]
        tok_s_list = [r["decode_tok_s"] for r in api_records if r.get("decode_tok_s", 0) > 0]
        tokens_list = [r["tokens_generated"] for r in api_records if r.get("tokens_generated", 0) > 0]

        result = {
            "test": test,
            "provider": provider,
            "prompt": prompt,
            "rounds": len(group),
            "ttft_ms_median": round(statistics.median(ttft_list)) if ttft_list else 0,
            "ttft_ms_stdev": round(statistics.stdev(ttft_list), 2) if len(ttft_list) > 1 else 0,
            # token 相关: 只有 api 数据才输出，否则 None
            "decode_tok_s_median": round(statistics.median(tok_s_list), 2) if tok_s_list else None,
            "decode_tok_s_mean": round(statistics.mean(tok_s_list), 2) if tok_s_list else None,
            "decode_tok_s_stdev": round(statistics.stdev(tok_s_list), 2) if len(tok_s_list) > 1 else None,
            "total_ms_median": round(statistics.median(total_ms_list)),
            "tokens_median": round(statistics.median(tokens_list)) if tokens_list else None,
            "memory_peak_mb": max(mem_list) if mem_list else 0,
        }
        results.append(result)

    # ---- B1 多轮分析: 按 (test, provider, turn) 分组，计算 T2/T1 ratio ----
    multi_turn_results = []
    mt_records = [r for r in valid if "turn" in r]
    if mt_records:
        mt_groups = {}
        for r in mt_records:
            key = (r.get("test_name", ""), r.get("provider", ""), r.get("turn"))
            mt_groups.setdefault(key, []).append(r)

        # 先按 (test, provider) 聚合两个 turn 的中位数，再算 ratio
        provider_turns = {}  # (test, provider) → {1: ttft_median, 2: ttft_median}
        for (test, provider, turn), group in sorted(mt_groups.items()):
            ttft_list = [r["ttft_ms"] for r in group if r.get("ttft_ms", 0) > 0]
            if not ttft_list:
                continue
            ttft_median = round(statistics.median(ttft_list))

            # token 相关: 只用 api 数据
            api_records = [r for r in group if r.get("token_source") == "api"]
            tok_s_list = [r["decode_tok_s"] for r in api_records if r.get("decode_tok_s", 0) > 0]

            entry = {
                "test": test,
                "provider": provider,
                "turn": turn,
                "rounds": len(group),
                "ttft_ms_median": ttft_median,
                "ttft_ms_stdev": round(statistics.stdev(ttft_list), 2) if len(ttft_list) > 1 else 0,
                "decode_tok_s_median": round(statistics.median(tok_s_list), 2) if tok_s_list else None,
            }
            multi_turn_results.append(entry)
            provider_turns.setdefault((test, provider), {})[turn] = ttft_median

        # 回填 t2_t1_ratio (TTFT₂ / TTFT₁, >1 表示 T2 更慢)
        for entry in multi_turn_results:
            turns = provider_turns.get((entry["test"], entry["provider"]), {})
            if entry["turn"] == 2 and turns.get(1) and turns.get(2):
                entry["t2_t1_ratio"] = round(turns[2] / turns[1], 2) if turns[1] > 0 else None
            else:
                entry["t2_t1_ratio"] = None

    return results, multi_turn_results, has_estimated_tokens


def generate_summary(results, run_dir, has_estimated_tokens=False, multi_turn_results=None):
    """生成 Markdown 格式的汇总表"""
    results_dir = Path(run_dir) / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    lines = ["# RUN 结果汇总\n"]

    if has_estimated_tokens:
        lines.append("> ⚠️ 部分数据的 token 计数为估算值（token_source: estimated），"
                     "decode_tok_s 等指标可能存在偏差。\n")

    # 按测试组分组展示
    tests = {}
    for r in results:
        tests.setdefault(r["test"], []).append(r)

    for test, group in tests.items():
        lines.append(f"\n## {test}\n")
        lines.append("| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |")
        lines.append("|----------|--------|--------|--------------|---------------|--------------|----------------|---------|")

        for r in sorted(group, key=lambda x: (x["prompt"], x["provider"])):
            tok_s = r['decode_tok_s_median'] if r['decode_tok_s_median'] is not None else "N/A"
            tok_s_std = r['decode_tok_s_stdev'] if r['decode_tok_s_stdev'] is not None else "N/A"
            lines.append(
                f"| {r['provider']} | {r['prompt']} | {r['rounds']} | "
                f"{r['ttft_ms_median']}ms | "
                f"{tok_s} | {tok_s_std} | "
                f"{r['total_ms_median']}ms | {r['memory_peak_mb']}MB |"
            )

    # ---- B1 多轮缓存分析 ----
    if multi_turn_results:
        # 按 test 分组
        mt_tests = {}
        for r in multi_turn_results:
            mt_tests.setdefault(r["test"], []).append(r)

        for test, group in mt_tests.items():
            lines.append(f"\n## {test} — 多轮缓存分析\n")
            lines.append("| Provider | Turn | Rounds | TTFT (median) | TTFT stdev | tok/s (median) | T2/T1 Ratio |")
            lines.append("|----------|------|--------|--------------|-----------|---------------|------------|")

            for r in sorted(group, key=lambda x: (x["provider"], x["turn"])):
                speedup = f"{r['t2_t1_ratio']}" if r.get("t2_t1_ratio") else "—"
                tok_s = r['decode_tok_s_median'] if r['decode_tok_s_median'] is not None else "N/A"
                lines.append(
                    f"| {r['provider']} | T{r['turn']} | {r['rounds']} | "
                    f"{r['ttft_ms_median']}ms | {r['ttft_ms_stdev']} | "
                    f"{tok_s} | {speedup} |"
                )

    summary_path = results_dir / "summary.md"
    with open(summary_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"报告已生成: {summary_path}")


def generate_csv(results, run_dir, multi_turn_results=None):
    """生成 CSV 供后续分析或导入电子表格"""
    results_dir = Path(run_dir) / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    csv_path = results_dir / "raw.csv"
    headers = ["test", "provider", "prompt", "rounds",
               "ttft_ms_median", "ttft_ms_stdev",
               "decode_tok_s_median", "decode_tok_s_mean", "decode_tok_s_stdev",
               "total_ms_median", "tokens_median", "memory_peak_mb"]

    with open(csv_path, "w") as f:
        f.write(",".join(headers) + "\n")
        for r in results:
            f.write(",".join(str(r.get(h, "")) if r.get(h) is not None else "" for h in headers) + "\n")

    print(f"CSV 已生成: {csv_path}")

    # ---- B1 多轮数据单独输出 ----
    if multi_turn_results:
        mt_csv_path = results_dir / "multi_turn.csv"
        mt_headers = ["test", "provider", "turn", "rounds",
                      "ttft_ms_median", "ttft_ms_stdev",
                      "decode_tok_s_median", "t2_t1_ratio"]
        with open(mt_csv_path, "w") as f:
            f.write(",".join(mt_headers) + "\n")
            for r in multi_turn_results:
                f.write(",".join(str(r.get(h, "")) if r.get(h) is not None else "" for h in mt_headers) + "\n")
        print(f"多轮 CSV 已生成: {mt_csv_path}")


def analyze_token_count(run_dir):
    """
    T1 场景独立分析: 非流式精确 token 计数

    T1 数据用于:
    1. 提供 oMLX/mlx-lm 的精确 completion_tokens（流式场景无法获取）
    2. 结合流式场景的总耗时，计算修正后的 tok/s
    3. 交叉验证 Ollama API 返回的 token 数是否一致
    """
    run_path = Path(run_dir)

    # 查找 T1 场景目录
    t1_dirs = [d for d in (run_path / "scenarios").iterdir()
               if d.name.startswith("T1") and (d / "data").is_dir()] if (run_path / "scenarios").is_dir() else []

    if not t1_dirs:
        return None

    t1_results = []
    for t1_dir in t1_dirs:
        data_dir = t1_dir / "data"
        for provider_dir in data_dir.iterdir():
            if not provider_dir.is_dir() or provider_dir.name.startswith("."): continue
            provider = provider_dir.name
            records = []
            for f in sorted(provider_dir.glob("round_*.json")):
                try:
                    r = json.load(open(f))
                    if not r.get("is_warmup", False):
                        records.append(r)
                except: pass

            if not records: continue

            tokens = [r["completion_tokens"] for r in records if r.get("completion_tokens", 0) > 0]
            total_ms = [r["total_time_ms"] for r in records if r.get("total_time_ms", 0) > 0]

            if not tokens: continue

            t1_results.append({
                "provider": provider,
                "scenario": t1_dir.name,
                "rounds": len(records),
                "completion_tokens_median": round(statistics.median(tokens)),
                "completion_tokens_stdev": round(statistics.stdev(tokens), 2) if len(tokens) > 1 else 0,
                "total_ms_median": round(statistics.median(total_ms)) if total_ms else 0,
                "samples": tokens,
            })

    return t1_results if t1_results else None


def generate_token_report(t1_results, run_dir):
    """
    生成 T1 独立报告

    T1 是独立场景，只输出自己的精确 token 数据。
    不做跨场景修正——每个场景 prompt 不同，token 数不同，修正无意义。
    """
    results_dir = Path(run_dir) / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    lines = ["# T1: 非流式精确 Token 计数\n"]
    lines.append("> 独立场景，用非流式请求采集精确 completion_tokens。\n")

    lines.append("## 数据\n")
    lines.append("| Provider | Rounds | Tokens (median) | Tokens (stdev) | 非流式总耗时 (median) |")
    lines.append("|----------|--------|----------------|----------------|---------------------|")
    for r in sorted(t1_results, key=lambda x: x["provider"]):
        lines.append(
            f"| {r['provider']} | {r['rounds']} | "
            f"{r['completion_tokens_median']} | {r['completion_tokens_stdev']} | "
            f"{r['total_ms_median']}ms |"
        )

    lines.append("\n## 适用范围\n")
    lines.append("- T1 prompt 与 A1 相同（\"用一段话解释 RAG 的工作原理\"）")
    lines.append("- T1 数据**仅可参考对比 A1 场景**的 token 量级")
    lines.append("- A2/A3/E1/E2 的 prompt 不同，T1 数据**不适用于修正**这些场景的 tok/s")
    lines.append("- 如需其他场景的精确 token 数，应新建对应的 T 场景独立采集")

    token_report_path = results_dir / "token_analysis.md"
    with open(token_report_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Token 分析报告: {token_report_path}")

    # CSV
    csv_path = results_dir / "token_count.csv"
    with open(csv_path, "w") as f:
        f.write("provider,rounds,completion_tokens_median,completion_tokens_stdev,total_ms_median\n")
        for r in t1_results:
            f.write(f"{r['provider']},{r['rounds']},{r['completion_tokens_median']},{r['completion_tokens_stdev']},{r['total_ms_median']}\n")
    print(f"Token CSV: {csv_path}")


def main():
    if len(sys.argv) < 2:
        print("用法: python3 analyze.py <run_dir>")
        sys.exit(1)

    run_dir = sys.argv[1]
    print(f"分析数据: {run_dir}")

    records = load_run_data(run_dir)
    if not records:
        print("ERROR: 没有找到测试数据")
        sys.exit(1)

    print(f"加载了 {len(records)} 条记录")

    results, multi_turn_results, has_estimated_tokens = analyze(records)
    if has_estimated_tokens:
        print("WARNING: 部分记录的 token 计数为估算值 (token_source: estimated)，tok/s 显示 N/A", file=sys.stderr)
    if multi_turn_results:
        print(f"检测到 B1 多轮数据: {len(multi_turn_results)} 条分组")

    generate_summary(results, run_dir, has_estimated_tokens, multi_turn_results)
    generate_csv(results, run_dir, multi_turn_results)

    # T1 token 补充分析
    t1_results = analyze_token_count(run_dir)
    if t1_results:
        print(f"检测到 T1 token 计数数据: {len(t1_results)} 个 provider")
        generate_token_report(t1_results, run_dir)
    else:
        print("未检测到 T1 token 计数数据")


if __name__ == "__main__":
    main()
