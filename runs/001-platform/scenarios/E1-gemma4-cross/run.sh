#!/bin/bash
# ============================================================================
# 单轮请求测试 — 使用 lib.sh 共享函数
# ============================================================================
# 用法:
#   bash run.sh              # 跑全部 provider
#   bash run.sh ollama       # 只跑指定 provider
#   bash run.sh --list
# ============================================================================

set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(cd "$SCENARIO_DIR/../.." && pwd)"
CONFIG="$SCENARIO_DIR/config.json"
DATA_DIR="$SCENARIO_DIR/data"

source "$RUN_DIR/lib.sh"

# ---- 参数 ----
FILTER_PROVIDER="${1:-}"

if [ "$FILTER_PROVIDER" = "--list" ]; then
    echo "可用 provider:"
    python3 -c "
import json
for p in json.load(open('$CONFIG'))['providers']:
    print(f'  {p[\"name\"]:10s}  {p[\"model\"]}')"
    exit 0
fi

[ "$FILTER_PROVIDER" = "--help" ] || [ "$FILTER_PROVIDER" = "-h" ] && { echo "用法: bash run.sh [provider|--list]"; exit 0; }

# ---- 读取配置 ----
eval "$(python3 -c "
import json
c = json.load(open('$CONFIG'))
print(f'SCENARIO_NAME=\"{c[\"name\"]}\"')
print(f'ROUNDS={c[\"rounds\"]}')
print(f'WARMUP={c[\"warmup\"]}')
print(f'TIMEOUT={c[\"timeout\"]}')
print(f'MAX_TOKENS={c[\"prompt\"][\"max_tokens\"]}')
")"

echo "=========================================="
echo " $SCENARIO_NAME"
echo " Rounds: $ROUNDS (warmup: $WARMUP)"
echo " Thinking: disabled"
[ -n "$FILTER_PROVIDER" ] && echo " Provider: $FILTER_PROVIDER"
echo "=========================================="

collect_sysinfo

# ---- 构造 messages ----
MESSAGES=$(build_messages "$CONFIG" "prompt")

# ---- 主循环 ----
PROVIDER_COUNT=$(python3 -c "import json; print(len(json.load(open('$CONFIG'))['providers']))")
MLX_LM_PID=""

for pidx in $(seq 0 $((PROVIDER_COUNT - 1))); do
    eval "$(load_provider "$CONFIG" "$pidx")"

    [ -n "$FILTER_PROVIDER" ] && [ "$P_NAME" != "$FILTER_PROVIDER" ] && continue

    P_DATA_DIR="$DATA_DIR/$P_NAME"
    if [ -d "$P_DATA_DIR" ]; then
        EXISTING=$(find "$P_DATA_DIR" -name "round_*.json" | wc -l | tr -d ' ')
    else
        EXISTING=0
    fi
    [ "$EXISTING" -ge "$ROUNDS" ] && { echo -e "\n>> 跳过 $P_NAME (已有 $EXISTING/$ROUNDS 条)\n   如需重跑: rm -rf $P_DATA_DIR"; continue; }

    cleanup_environment

    mkdir -p "$P_DATA_DIR"
    python3 -c "
import json, time
with open('$P_DATA_DIR/_env_baseline.json', 'w') as f:
    json.dump({'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'provider': '$P_NAME', 'model': '$P_MODEL', 'free_memory_mb': ${FREE_MEM:-0}}, f, indent=2)
"

    warmup_provider "$P_NAME" "$P_URL" "$P_KEY" "$P_MODEL" "$P_MANAGED"

    echo -e "\n>> $P_NAME | $P_MODEL | $ROUNDS 轮"

    for round in $(seq 1 $ROUNDS); do
        OUTPUT="$P_DATA_DIR/round_$(printf '%02d' $round).json"
        [ -f "$OUTPUT" ] && { printf "   [skip  %02d/$ROUNDS] 已存在\n" "$round"; continue; }

        [ "$round" -le "$WARMUP" ] && label="warmup" || label="round"
        printf "   [$label %02d/$ROUNDS] " "$round"

        MEM_BEFORE=$(get_memory "$P_NAME")
        CACHE_INFO=$(get_cache_info "$P_NAME" "$P_MODEL")
        send_request "$P_URL" "$P_KEY" "$P_MODEL" "$P_NAME" "$OUTPUT" "$MESSAGES" "$MAX_TOKENS" > /dev/null
        MEM_AFTER=$(get_memory "$P_NAME")

        # 如果 API 返回错误导致 0 token 文件，analyze.py 会过滤掉 (decode_tok_s == 0)。
        # 重跑时 rm 该文件即可。
        if [ -f "$OUTPUT" ]; then
            IS_WARMUP=$( [ "$round" -le "$WARMUP" ] && echo "True" || echo "False" )
            append_metadata "$OUTPUT" "$MEM_BEFORE" "$MEM_AFTER" "$IS_WARMUP" "$round" "$CACHE_INFO"
            print_round_result "$OUTPUT" "$MEM_BEFORE" "$MEM_AFTER"
        else
            echo "FAILED"
        fi

        # 轮间清理: 卸载模型消除 KV cache，确保下一轮是无缓存的冷启动
        inter_round_cleanup "$P_NAME" "$P_MODEL" "$P_KEY" "$P_URL" "$P_MANAGED"
    done

    stop_provider "$P_NAME"
done

echo -e "\n==========================================\n 完成！数据: $DATA_DIR/\n=========================================="
