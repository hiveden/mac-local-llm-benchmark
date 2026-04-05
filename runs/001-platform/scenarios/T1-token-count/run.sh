#!/bin/bash
# ============================================================================
# T1: 非流式精确 Token 计数 — 独立补充场景
# ============================================================================
# 用法:
#   bash run.sh              # 跑全部 provider
#   bash run.sh omlx         # 只跑指定 provider
#   bash run.sh --list
# ============================================================================

set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(cd "$SCENARIO_DIR/../.." && pwd)"
CONFIG="$SCENARIO_DIR/config.json"
DATA_DIR="$SCENARIO_DIR/data"

source "$RUN_DIR/lib.sh"

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
echo " $SCENARIO_NAME (非流式)"
echo " Rounds: $ROUNDS (warmup: $WARMUP)"
echo "=========================================="

collect_sysinfo

MESSAGES=$(build_messages "$CONFIG" "prompt")

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

    echo -e "\n>> $P_NAME | $P_MODEL | $ROUNDS 轮 (非流式)"

    for round in $(seq 1 $ROUNDS); do
        OUTPUT="$P_DATA_DIR/round_$(printf '%02d' $round).json"
        [ -f "$OUTPUT" ] && { printf "   [skip  %02d/$ROUNDS] 已存在\n" "$round"; continue; }

        [ "$round" -le "$WARMUP" ] && label="warmup" || label="round"
        printf "   [$label %02d/$ROUNDS] " "$round"

        # 非流式请求：按 provider 分支
        if [ "$P_NAME" = "ollama" ]; then
            OLLAMA_BASE="${P_URL%/v1}"
            START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
            RESP=$(curl -s --noproxy '*' --max-time "$TIMEOUT" "$OLLAMA_BASE/api/chat" \
                -H "Content-Type: application/json" \
                -d "{\"model\": \"$P_MODEL\", \"messages\": $MESSAGES, \"think\": false, \"stream\": false, \"options\": {\"num_predict\": $MAX_TOKENS}}" 2>/dev/null)
            END_MS=$(python3 -c "import time; print(int(time.time()*1000))")

            echo "$RESP" | OUTFILE="$OUTPUT" START="$START_MS" END="$END_MS" PNAME="$P_NAME" MNAME="$P_MODEL" python3 -c "
import sys, json, os
resp = json.load(sys.stdin)
total_ms = int(os.environ['END']) - int(os.environ['START'])
metrics = {
    'provider': os.environ['PNAME'],
    'model': os.environ['MNAME'],
    'prompt_tokens': resp.get('prompt_eval_count', 0),
    'completion_tokens': resp.get('eval_count', 0),
    'total_time_ms': total_ms,
    'response': resp.get('message', {}).get('content', ''),
    'stream': False
}
with open(os.environ['OUTFILE'], 'w') as f:
    json.dump(metrics, f, indent=2, ensure_ascii=False)
"
        else
            # oMLX / mlx-lm
            args=(-s --noproxy '*' --max-time "$TIMEOUT" "$P_URL/chat/completions" -H "Content-Type: application/json")
            [ -n "$P_KEY" ] && args+=(-H "Authorization: Bearer $P_KEY")
            extra=""
            [ "$P_NAME" = "omlx" ] && extra=", \"chat_template_kwargs\": {\"enable_thinking\": false}"

            api_model="$P_MODEL"
            if [ "$P_NAME" = "mlx-lm" ]; then
                api_model=$(curl -s --noproxy '*' "$P_URL/models" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('data',[{}])[0].get('id','default'))
" 2>/dev/null || echo "$P_MODEL")
            fi

            args+=(-d "{\"model\": \"$api_model\", \"messages\": $MESSAGES, \"max_tokens\": $MAX_TOKENS, \"stream\": false${extra}}")

            START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
            RESP=$(curl "${args[@]}" 2>/dev/null)
            END_MS=$(python3 -c "import time; print(int(time.time()*1000))")

            echo "$RESP" | OUTFILE="$OUTPUT" START="$START_MS" END="$END_MS" PNAME="$P_NAME" MNAME="$P_MODEL" python3 -c "
import sys, json, os
resp = json.load(sys.stdin)
usage = resp.get('usage', {})
total_ms = int(os.environ['END']) - int(os.environ['START'])
metrics = {
    'provider': os.environ['PNAME'],
    'model': os.environ['MNAME'],
    'prompt_tokens': usage.get('prompt_tokens', 0),
    'completion_tokens': usage.get('completion_tokens', 0),
    'total_time_ms': total_ms,
    'response': resp.get('choices', [{}])[0].get('message', {}).get('content', ''),
    'stream': False
}
with open(os.environ['OUTFILE'], 'w') as f:
    json.dump(metrics, f, indent=2, ensure_ascii=False)
"
        fi

        # 追加元数据
        if [ -f "$OUTPUT" ]; then
            TOKENS=$(python3 -c "import json; print(json.load(open('$OUTPUT')).get('completion_tokens', 0))")
            TOTAL=$(python3 -c "import json; print(json.load(open('$OUTPUT')).get('total_time_ms', 0))")

            IS_WARMUP=$( [ "$round" -le "$WARMUP" ] && echo "True" || echo "False" )
            python3 -c "
import json
with open('$OUTPUT') as f: d = json.load(f)
d['is_warmup'] = $IS_WARMUP
d['round'] = $round
with open('$OUTPUT', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
"
            echo "${TOKENS} tokens | ${TOTAL}ms"
        else
            echo "FAILED"
        fi
    done

    stop_provider "$P_NAME"
done

echo -e "\n==========================================\n 完成！数据: $DATA_DIR/\n=========================================="
