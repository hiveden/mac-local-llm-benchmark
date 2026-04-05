#!/bin/bash
# ============================================================================
# B1: 多轮对话 — 缓存命中测试（使用 lib.sh 共享函数）
# ============================================================================
#
# 与 A1-A3 不同，每轮包含两次请求：
#   Turn 1: 发送初始问题 → 记录 TTFT₁ → 拿到回答
#   Turn 2: 带历史追问 → 记录 TTFT₂ → 对比缓存效果
#
# 每轮结束后卸载模型并重新预热，确保下一轮 Turn 1 是无缓存的干净状态。
#
# 用法:
#   bash run.sh                    # 跑全部
#   bash run.sh ollama             # 只跑指定 provider
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
print(f'MAX_TOKENS={c[\"prompts\"][\"turn1\"][\"max_tokens\"]}')
print(f'MAX_TOKENS_T2={c[\"prompts\"][\"turn2\"][\"max_tokens\"]}')
")"

echo "=========================================="
echo " $SCENARIO_NAME"
echo " Rounds: $ROUNDS × 2 turns (warmup: $WARMUP)"
echo " Thinking: disabled"
[ -n "$FILTER_PROVIDER" ] && echo " Provider: $FILTER_PROVIDER"
echo "=========================================="

collect_sysinfo

# ---- 构造 Turn 1 messages ----
TURN1_MSGS=$(python3 -c "
import json
p = json.load(open('$CONFIG'))['prompts']['turn1']
msgs = []
if p.get('system'): msgs.append({'role': 'system', 'content': p['system']})
msgs.append({'role': 'user', 'content': p['user']})
print(json.dumps(msgs))
")

# ---- 读取 Turn 2 追问文本（用于拼接历史后构造 Turn 2 messages）----
TURN2_USER=$(python3 -c "import json; print(json.load(open('$CONFIG'))['prompts']['turn2']['user'])")
TURN1_SYSTEM=$(python3 -c "import json; print(json.load(open('$CONFIG'))['prompts']['turn1'].get('system',''))")
TURN1_USER=$(python3 -c "import json; print(json.load(open('$CONFIG'))['prompts']['turn1']['user'])")

# ---- 主循环 ----
PROVIDER_COUNT=$(python3 -c "import json; print(len(json.load(open('$CONFIG'))['providers']))")
MLX_LM_PID=""

for pidx in $(seq 0 $((PROVIDER_COUNT - 1))); do
    eval "$(load_provider "$CONFIG" "$pidx")"

    [ -n "$FILTER_PROVIDER" ] && [ "$P_NAME" != "$FILTER_PROVIDER" ] && continue

    P_DATA_DIR="$DATA_DIR/$P_NAME"
    if [ -d "$P_DATA_DIR" ]; then
        EXISTING=$(find "$P_DATA_DIR" -name "round_*_turn*.json" | wc -l | tr -d ' ')
    else
        EXISTING=0
    fi
    EXPECTED=$((ROUNDS * 2))
    [ "$EXISTING" -ge "$EXPECTED" ] && { echo -e "\n>> 跳过 $P_NAME (已有 $EXISTING/$EXPECTED 条数据)\n   如需重跑: rm -rf $P_DATA_DIR"; continue; }

    cleanup_environment

    mkdir -p "$P_DATA_DIR"
    python3 -c "
import json, time
with open('$P_DATA_DIR/_env_baseline.json', 'w') as f:
    json.dump({'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'provider': '$P_NAME', 'model': '$P_MODEL', 'free_memory_mb': ${FREE_MEM:-0}}, f, indent=2)
"

    warmup_provider "$P_NAME" "$P_URL" "$P_KEY" "$P_MODEL" "$P_MANAGED"

    echo -e "\n>> $P_NAME | $P_MODEL | $ROUNDS 轮 × 2 turns"

    for round in $(seq 1 $ROUNDS); do
        OUTPUT_T1="$P_DATA_DIR/round_$(printf '%02d' $round)_turn1.json"
        OUTPUT_T2="$P_DATA_DIR/round_$(printf '%02d' $round)_turn2.json"

        # 跳过已完成的轮次
        if [ -f "$OUTPUT_T1" ] && [ -f "$OUTPUT_T2" ]; then
            printf "   [skip  %02d/$ROUNDS] 已存在\n" "$round"
            continue
        fi

        [ "$round" -le "$WARMUP" ] && label="warmup" || label="round"

        # ---- Turn 1 ----
        printf "   [$label %02d/$ROUNDS T1] " "$round"

        MEM_BEFORE=$(get_memory "$P_NAME")
        CACHE_BEFORE=$(get_cache_info "$P_NAME" "$P_MODEL")
        # TURN1_RESPONSE 通过环境变量传递是安全的：
        # bash 双引号保护特殊字符，Python os.environ.get() + json.dumps() 正确序列化
        TURN1_RESPONSE=$(send_request "$P_URL" "$P_KEY" "$P_MODEL" "$P_NAME" "$OUTPUT_T1" "$TURN1_MSGS" "$MAX_TOKENS")
        MEM_AFTER=$(get_memory "$P_NAME")

        if [ -f "$OUTPUT_T1" ]; then
            IS_WARMUP=$( [ "$round" -le "$WARMUP" ] && echo "True" || echo "False" )
            # 追加 turn 字段
            python3 -c "
import json
with open('$OUTPUT_T1') as f: d = json.load(f)
d['turn'] = 1
with open('$OUTPUT_T1', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
"
            append_metadata "$OUTPUT_T1" "$MEM_BEFORE" "$MEM_AFTER" "$IS_WARMUP" "$round" "$CACHE_BEFORE"
            print_round_result "$OUTPUT_T1" "$MEM_BEFORE" "$MEM_AFTER"
        else
            echo "FAILED"; continue
        fi

        # 检查 Turn 1 是否有有效输出，空响应则跳过 Turn 2
        T1_TOKENS=$(python3 -c "import json; print(json.load(open('$OUTPUT_T1')).get('tokens_generated', 0))")
        if [ "$T1_TOKENS" -eq 0 ]; then
            echo "   Turn 1 无有效输出，跳过 Turn 2"
            continue
        fi

        # ---- Turn 2: 构造带历史的 messages ----
        printf "   [$label %02d/$ROUNDS T2] " "$round"

        TURN2_MSGS=$(SYSP="$TURN1_SYSTEM" USR1="$TURN1_USER" RESP1="$TURN1_RESPONSE" USR2="$TURN2_USER" python3 -c "
import json, os
sys_p = os.environ.get('SYSP', '')
usr1 = os.environ.get('USR1', '')
resp1 = os.environ.get('RESP1', '')
usr2 = os.environ.get('USR2', '')
msgs = []
if sys_p: msgs.append({'role': 'system', 'content': sys_p})
msgs.append({'role': 'user', 'content': usr1})
msgs.append({'role': 'assistant', 'content': resp1})
msgs.append({'role': 'user', 'content': usr2})
print(json.dumps(msgs))
")

        MEM_BEFORE=$(get_memory "$P_NAME")
        CACHE_BEFORE=$(get_cache_info "$P_NAME" "$P_MODEL")
        send_request "$P_URL" "$P_KEY" "$P_MODEL" "$P_NAME" "$OUTPUT_T2" "$TURN2_MSGS" "$MAX_TOKENS_T2" > /dev/null
        MEM_AFTER=$(get_memory "$P_NAME")

        if [ -f "$OUTPUT_T2" ]; then
            IS_WARMUP=$( [ "$round" -le "$WARMUP" ] && echo "True" || echo "False" )
            python3 -c "
import json
with open('$OUTPUT_T2') as f: d = json.load(f)
d['turn'] = 2
with open('$OUTPUT_T2', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
"
            append_metadata "$OUTPUT_T2" "$MEM_BEFORE" "$MEM_AFTER" "$IS_WARMUP" "$round" "$CACHE_BEFORE"
            print_round_result "$OUTPUT_T2" "$MEM_BEFORE" "$MEM_AFTER"
        else
            echo "FAILED"
        fi

        # ---- 轮间清理：卸载模型清除缓存，确保下一轮 Turn 1 是无缓存状态 ----
        case "$P_NAME" in
            ollama)
                ollama stop "$P_MODEL" 2>/dev/null || true
                ;;
            omlx)
                local_omlx_base=$(python3 -c "
import json
ps = json.load(open('$CONFIG'))['providers']
omlx = next((p for p in ps if p['name']=='omlx'), None)
print(omlx['base_url'].replace('/v1','') if omlx else '')
" 2>/dev/null || echo "")
                # 重新 login 确保 cookie 有效（长时间测试中 cookie 可能过期）
                curl -s --noproxy '*' -c /tmp/omlx-bench-cookies.txt \
                    "$local_omlx_base/admin/api/login" \
                    -X POST -H "Content-Type: application/json" \
                    -d "{\"api_key\": \"$P_KEY\"}" > /dev/null 2>&1 || true
                # 查实际 loaded model ID 再 unload（config 模型名可能与 loaded ID 不同）
                for loaded_id in $(curl -s --noproxy '*' -H "Authorization: Bearer $P_KEY" \
                    "$local_omlx_base/v1/models" 2>/dev/null | python3 -c "
import sys,json
try:
    for m in json.load(sys.stdin).get('data',[]):
        print(m['id'])
except: pass
" 2>/dev/null || true); do
                    UNLOAD_RESULT=$(curl -s --noproxy '*' -b /tmp/omlx-bench-cookies.txt \
                        "$local_omlx_base/admin/api/models/$loaded_id/unload" -X POST 2>&1 || echo '{"error":"curl failed"}')
                    echo "   oMLX unload $loaded_id: $UNLOAD_RESULT"
                done
                ;;
            # mlx-lm: 无持久化缓存，不需要清理
        esac

        # 等待模型卸载和内存释放（oMLX unload 是异步的）
        sleep 5

        # 重新预热（重新加载模型，模拟干净状态）
        # mlx-lm 无跨请求缓存，跳过轮间重启避免多余 JIT 干扰
        if [ "$P_NAME" != "mlx-lm" ]; then
            warmup_provider "$P_NAME" "$P_URL" "$P_KEY" "$P_MODEL" "$P_MANAGED"
        fi
    done

    stop_provider "$P_NAME"
done

echo -e "\n==========================================\n 完成！数据: $DATA_DIR/\n=========================================="
