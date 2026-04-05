#!/bin/bash
# ============================================================================
# lib.sh — RUN 01 共享函数库
# ============================================================================
#
# 被各场景的 run.sh source 引用。包含所有场景共用的函数：
# - collect_sysinfo: 系统信息采集
# - cleanup_environment: 环境清理（卸载模型、释放内存）
# - get_memory: 获取 provider 内存占用
# - get_cache_info: 获取缓存状态
# - warmup_provider: 预热 provider
# - stop_provider: 停止非托管 provider
# - send_stream_ollama: Ollama NDJSON 流式请求
# - send_stream_sse: oMLX/mlx-lm SSE 流式请求
#
# 依赖变量（调用方需设置）：
#   CONFIG — 场景 config.json 路径
#   RUN_DIR — RUN 根目录
#   TIMEOUT — 请求超时秒数
#   MAX_TOKENS — 最大生成 token 数
#
# 全局状态：
#   FREE_MEM — cleanup_environment 设置
#   MLX_LM_PID — warmup_provider/stop_provider 管理
# ============================================================================

# ---- 系统信息采集 ----
collect_sysinfo() {
    if [ ! -f "$RUN_DIR/sysinfo.json" ]; then
        echo ""
        echo ">> 采集系统信息..."
        python3 -c "
import json, subprocess

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode().strip()
    except:
        return 'unknown'

chip = run('sysctl -n machdep.cpu.brand_string')
if chip == 'unknown':
    chip = run(\"system_profiler SPHardwareDataType | grep 'Chip' | awk -F': ' '{print \$2}'\")

info = {
    'timestamp': run('date -u +%Y-%m-%dT%H:%M:%SZ'),
    'hardware': {
        'chip': chip,
        'cores_total': int(run('sysctl -n hw.ncpu') or '0'),
        'memory_gb': int(int(run('sysctl -n hw.memsize') or '0') / 1024**3),
        'os': run('sw_vers -productName') + ' ' + run('sw_vers -productVersion')
    },
    'software': {
        'ollama': run('ollama --version').split()[-1],
        'omlx': run('brew list --versions omlx').split()[-1] if 'omlx' in run('brew list --versions omlx') else 'unknown',
        'mlx_lm': run(\"python3 -c 'import mlx_lm; print(mlx_lm.__version__)'\"),
        'python': run('python3 --version').split()[-1]
    }
}
with open('$RUN_DIR/sysinfo.json', 'w') as f:
    json.dump(info, f, indent=2)
print('   已保存 sysinfo.json')
"
    fi
}

# ---- 环境清理 ----
# || true: 清理失败不阻塞测试。oMLX/Ollama 服务异常时宁可继续跑（数据会被缓存状态字段记录）
cleanup_environment() {
    echo ""
    echo ">> ---- 环境清理 ----"

    # Ollama
    for m in $(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' || true); do
        echo "   卸载 Ollama: $m"
        ollama stop "$m" 2>/dev/null || true
    done

    # oMLX
    local omlx_key omlx_base
    omlx_key=$(python3 -c "
import json
ps = json.load(open('$CONFIG'))['providers']
omlx = next((p for p in ps if p['name']=='omlx'), None)
print(omlx['api_key'] if omlx else '')
" 2>/dev/null || echo "")
    omlx_base=$(python3 -c "
import json
ps = json.load(open('$CONFIG'))['providers']
omlx = next((p for p in ps if p['name']=='omlx'), None)
print(omlx['base_url'].replace('/v1','') if omlx else '')
" 2>/dev/null || echo "")
    if [ -n "$omlx_base" ] && [ -n "$omlx_key" ]; then
        curl -s --noproxy '*' -c /tmp/omlx-bench-cookies.txt \
            "$omlx_base/admin/api/login" \
            -X POST -H "Content-Type: application/json" \
            -d "{\"api_key\": \"$omlx_key\"}" > /dev/null 2>&1 || true
        for m in $(curl -s --noproxy '*' -H "Authorization: Bearer $omlx_key" \
            "$omlx_base/v1/models" 2>/dev/null | python3 -c "
import sys,json
try:
    for m in json.load(sys.stdin).get('data',[]):
        print(m['id'])
except: pass
" 2>/dev/null || true); do
            echo "   卸载 oMLX: $m"
            curl -s --noproxy '*' -b /tmp/omlx-bench-cookies.txt \
                "$omlx_base/admin/api/models/$m/unload" -X POST > /dev/null 2>&1 || true
        done
    fi

    # mlx-lm
    pkill -f "mlx_lm.server" 2>/dev/null || true

    echo "   等待内存释放..."
    sleep 5

    FREE_MEM=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub(/\./,"",$3); print int($3*4096/1024/1024)}' || echo "0")
    echo "   空闲内存: ${FREE_MEM}MB"
}

# ---- 获取 provider 内存 (MB) ----
get_memory() {
    local provider_name="$1"
    local result=""
    case "$provider_name" in
        ollama)
            result=$(ollama ps 2>/dev/null | tail -n +2 | awk '{
                for(i=1;i<=NF;i++) {
                    if($(i+1)=="GB") { printf "%.0f", $i*1024; exit }
                    if($(i+1)=="MB") { printf "%.0f", $i; exit }
                }
            }' || true)
            ;;
        omlx)
            local pid=$(pgrep -f "omlx serve" | head -1 || true)
            [ -n "$pid" ] && result=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.0f", $1/1024}') || true
            ;;
        mlx-lm)
            [ -n "${MLX_LM_PID:-}" ] && kill -0 "$MLX_LM_PID" 2>/dev/null && \
                result=$(ps -o rss= -p "$MLX_LM_PID" 2>/dev/null | awk '{printf "%.0f", $1/1024}') || true
            ;;
    esac
    echo "${result:-0}"
}

# ---- 获取缓存状态 ----
get_cache_info() {
    local provider_name="$1"
    local model="$2"
    case "$provider_name" in
        ollama)
            local in_mem="false"
            ollama ps 2>/dev/null | grep -q "$model" && in_mem="true"
            echo "{\"type\": \"kv-cache-snapshot\", \"model_in_memory\": $in_mem}"
            ;;
        omlx)
            local omlx_base
            omlx_base=$(python3 -c "
import json
ps = json.load(open('$CONFIG'))['providers']
omlx = next((p for p in ps if p['name']=='omlx'), None)
print(omlx['base_url'].replace('/v1','') if omlx else '')
" 2>/dev/null || echo "")
            local stats=$(curl -s --noproxy '*' -b /tmp/omlx-bench-cookies.txt \
                "$omlx_base/admin/api/stats" 2>/dev/null || echo "{}")
            echo "$stats" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    cache={k:v for k,v in d.items() if 'cache' in k.lower() or 'hit' in k.lower()}
    if not cache: cache={'raw_keys': list(d.keys())[:10]}
    print(json.dumps({'type':'ssd-kv-cache','stats':cache}))
except:
    print(json.dumps({'type':'ssd-kv-cache','stats':{},'error':'fetch_failed'}))
" 2>/dev/null
            ;;
        mlx-lm)
            echo "{\"type\": \"none\"}"
            ;;
    esac
}

# ---- 预热 provider ----
warmup_provider() {
    local provider_name="$1"
    local base_url="$2"
    local api_key="$3"
    local model="$4"
    local managed="$5"

    echo ">> 预热 $provider_name: $model"

    if [ "$managed" = "false" ]; then
        local port=$(echo "$base_url" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
        # 如果 mlx-lm 已在运行，跳过启动，只发预热请求
        if curl -s --noproxy '*' "$base_url/models" &>/dev/null; then
            # 已在运行，获取 PID 供 get_memory 使用
            MLX_LM_PID=$(pgrep -f "mlx_lm.server" | head -1 || true)
            echo "   mlx-lm 已在运行 (port $port, PID: ${MLX_LM_PID:-unknown})，跳过启动"
        else
            local expanded_model="${model/#\~/$HOME}"
            echo "   启动 mlx-lm server on port $port..."
            python3 -m mlx_lm.server --model "$expanded_model" --port "$port" \
                --chat-template-args '{"enable_thinking":false}' \
                --prompt-cache-size 0 &>/tmp/mlx-lm-server.log &
            MLX_LM_PID=$!
            for i in $(seq 1 60); do
                curl -s --noproxy '*' "$base_url/models" &>/dev/null && break
                sleep 2
            done
            echo "   mlx-lm 就绪 (PID: $MLX_LM_PID)"
        fi
        # 检查是否真的就绪
        if ! curl -s --noproxy '*' "$base_url/models" &>/dev/null; then
            echo "   ERROR: mlx-lm 启动超时" >&2
            return 1
        fi
        # 发预热请求触发首次推理 JIT（与 ollama/omlx 对齐）
        curl -s --noproxy '*' "$base_url/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"default\", \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}], \"max_tokens\": 5, \"stream\": false}" \
            -o /dev/null 2>/dev/null
    elif [ "$provider_name" = "ollama" ]; then
        local ollama_base="${base_url%/v1}"
        if ! curl -s --noproxy '*' --max-time 120 "$ollama_base/api/chat" \
            -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}], \"stream\": false, \"think\": false}" \
            -o /dev/null 2>/dev/null; then
            echo "   WARNING: Ollama warmup 失败（模型加载可能出错）" >&2
        fi
    else
        local -a args=(-s --noproxy '*' --max-time 120 "$base_url/chat/completions" -H "Content-Type: application/json")
        [ -n "$api_key" ] && args+=(-H "Authorization: Bearer $api_key")
        args+=(-d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}], \"max_tokens\": 5, \"stream\": false, \"chat_template_kwargs\": {\"enable_thinking\": false}}")
        if ! curl "${args[@]}" -o /dev/null 2>/dev/null; then
            echo "   WARNING: oMLX warmup 失败" >&2
        fi
    fi
}

# ---- 停止 provider ----
stop_provider() {
    local provider_name="$1"
    if [ "$provider_name" = "mlx-lm" ] && [ -n "${MLX_LM_PID:-}" ]; then
        echo "   停止 mlx-lm (PID: $MLX_LM_PID)"
        kill "$MLX_LM_PID" 2>/dev/null || true
        wait "$MLX_LM_PID" 2>/dev/null || true
        MLX_LM_PID=""
        pkill -f "mlx_lm.server" 2>/dev/null || true
    fi
}

# ---- 轮间清理（消除 KV cache / prompt cache 对下一轮的影响）----
# 参数: provider_name, model, api_key, base_url, managed
# 所有平台都做清理: 卸载/重启 → 等内存释放 → 重新预热
inter_round_cleanup() {
    local provider_name="$1"
    local model="$2"
    local api_key="$3"
    local base_url="$4"
    local managed="$5"

    case "$provider_name" in
        ollama)
            ollama stop "$model" 2>/dev/null || true
            ;;
        omlx)
            local omlx_base="${base_url%/v1}"
            curl -s --noproxy '*' -c /tmp/omlx-bench-cookies.txt \
                "$omlx_base/admin/api/login" \
                -X POST -H "Content-Type: application/json" \
                -d "{\"api_key\": \"$api_key\"}" > /dev/null 2>&1 || true
            for loaded_id in $(curl -s --noproxy '*' -H "Authorization: Bearer $api_key" \
                "$omlx_base/v1/models" 2>/dev/null | python3 -c "
import sys,json
try:
    for m in json.load(sys.stdin).get('data',[]):
        print(m['id'])
except: pass
" 2>/dev/null || true); do
                curl -s --noproxy '*' -b /tmp/omlx-bench-cookies.txt \
                    "$omlx_base/admin/api/models/$loaded_id/unload" -X POST > /dev/null 2>&1 || true
            done
            ;;
        mlx-lm)
            # mlx-lm 有 prompt cache（--prompt-cache-size 默认非零），重启 server 清除
            stop_provider "$provider_name"
            ;;
    esac

    sleep 5
    warmup_provider "$provider_name" "$base_url" "$api_key" "$model" "$managed"
}

# ---- Ollama NDJSON 流式请求 ----
# token 估算 fallback (len // 2) 仅在 API 不返回 token 计数时触发（正常不会）。
# 已通过 token_source: "estimated" 标记，analyze.py 会输出警告。
# 参数: base_url, model, messages_json, max_tokens, output_file, provider_name
send_stream_ollama() {
    local base_url="$1"
    local model="$2"
    local messages_json="$3"
    local max_tokens="$4"
    local output_file="$5"
    local provider_name="${6:-ollama}"

    local ollama_base="${base_url%/v1}"
    local -a curl_args=(-sN --noproxy '*' --max-time "$TIMEOUT" "$ollama_base/api/chat" -H "Content-Type: application/json")
    curl_args+=(-d "{\"model\": \"$model\", \"messages\": $messages_json, \"think\": false, \"stream\": true, \"options\": {\"num_predict\": $max_tokens}}")

    curl "${curl_args[@]}" 2>/dev/null | OUTFILE="$output_file" PNAME="$provider_name" MNAME="$model" python3 -c "
import sys, json, time, os

start_time = time.time()
first_token_time = None
full_content = ''
tokens_generated = 0
prompt_tokens = 0
completed = False

for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        chunk = json.loads(line)
    except json.JSONDecodeError:
        continue
    if chunk.get('done', False):
        tokens_generated = chunk.get('eval_count', tokens_generated)
        prompt_tokens = chunk.get('prompt_eval_count', prompt_tokens)
        completed = True
        break
    content = chunk.get('message', {}).get('content', '')
    if content:
        if first_token_time is None:
            first_token_time = time.time()
        full_content += content

end_time = time.time()
total_s = end_time - start_time
total_ms = int(total_s * 1000)
ttft_ms = int((first_token_time - start_time) * 1000) if first_token_time else total_ms
decode_time_s = (end_time - first_token_time) if first_token_time else total_s
token_source = 'api'
if tokens_generated == 0 and full_content:
    tokens_generated = max(1, len(full_content) // 2)
    token_source = 'estimated'
decode_tok_s = round(tokens_generated / decode_time_s, 2) if decode_time_s > 0 else 0

if not completed and full_content:
    token_source = 'partial'

metrics = {
    'provider': os.environ['PNAME'], 'model': os.environ['MNAME'],
    'prompt_tokens': prompt_tokens, 'tokens_generated': tokens_generated,
    'token_source': token_source, 'completed': completed,
    'total_time_ms': total_ms, 'ttft_ms': ttft_ms, 'decode_tok_s': decode_tok_s,
    'response': full_content, 'reasoning': None
}
with open(os.environ['OUTFILE'], 'w') as f:
    json.dump(metrics, f, indent=2, ensure_ascii=False)
print(full_content, end='')
"
}

# ---- oMLX/mlx-lm SSE 流式请求 ----
# 参数: base_url, api_key, model, messages_json, max_tokens, output_file, provider_name
send_stream_sse() {
    local base_url="$1"
    local api_key="$2"
    local model="$3"
    local messages_json="$4"
    local max_tokens="$5"
    local output_file="$6"
    local provider_name="${7:-omlx}"

    local -a curl_args=(-sN --noproxy '*' --max-time "$TIMEOUT" "$base_url/chat/completions" -H "Content-Type: application/json")
    [ -n "$api_key" ] && curl_args+=(-H "Authorization: Bearer $api_key")

    local extra_params=""
    [ "$provider_name" = "omlx" ] && extra_params=", \"chat_template_kwargs\": {\"enable_thinking\": false}"

    local api_model="$model"
    if [ "$provider_name" = "mlx-lm" ]; then
        api_model=$(curl -s --noproxy '*' "$base_url/models" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('data',[{}])[0].get('id','default'))
" 2>/dev/null || echo "$model")
    fi

    curl_args+=(-d "{\"model\": \"$api_model\", \"messages\": $messages_json, \"max_tokens\": $max_tokens, \"stream\": true${extra_params}}")

    curl "${curl_args[@]}" 2>/dev/null | OUTFILE="$output_file" PNAME="$provider_name" MNAME="$model" python3 -c "
import sys, json, time, os

start_time = time.time()
first_token_time = None
full_content = ''
full_reasoning = ''
tokens_generated = 0
prompt_tokens = 0
completed = False

for line in sys.stdin:
    line = line.strip()
    if not line.startswith('data:'): continue
    data_str = line[5:].lstrip()
    if data_str == '[DONE]':
        completed = True
        break
    try:
        chunk = json.loads(data_str)
    except json.JSONDecodeError:
        continue
    usage = chunk.get('usage', {})
    if usage.get('prompt_tokens', 0) > 0: prompt_tokens = usage['prompt_tokens']
    if usage.get('completion_tokens', 0) > 0: tokens_generated = usage['completion_tokens']
    choices = chunk.get('choices', [])
    if not choices: continue
    delta = choices[0].get('delta', {})
    content = delta.get('content', '')
    reasoning = delta.get('reasoning', '')
    token_text = content or reasoning
    if token_text:
        if first_token_time is None: first_token_time = time.time()
        if content: full_content += content
        if reasoning: full_reasoning += reasoning

end_time = time.time()
total_s = end_time - start_time
total_ms = int(total_s * 1000)
ttft_ms = int((first_token_time - start_time) * 1000) if first_token_time else total_ms
decode_time_s = (end_time - first_token_time) if first_token_time else total_s
token_source = 'api'
all_text = full_content or full_reasoning
if tokens_generated == 0 and all_text:
    tokens_generated = max(1, len(all_text) // 2)
    token_source = 'estimated'
if not completed and all_text:
    token_source = 'partial'
decode_tok_s = round(tokens_generated / decode_time_s, 2) if decode_time_s > 0 else 0

metrics = {
    'provider': os.environ['PNAME'], 'model': os.environ['MNAME'],
    'prompt_tokens': prompt_tokens, 'tokens_generated': tokens_generated,
    'token_source': token_source, 'completed': completed,
    'total_time_ms': total_ms, 'ttft_ms': ttft_ms, 'decode_tok_s': decode_tok_s,
    'response': full_content,
    'reasoning': full_reasoning if full_reasoning else None
}
with open(os.environ['OUTFILE'], 'w') as f:
    json.dump(metrics, f, indent=2, ensure_ascii=False)
print(full_content or full_reasoning, end='')
"
}

# ---- 发送请求（自动选择 provider 分支）----
# 参数: base_url, api_key, model, provider_name, output_file, messages_json, max_tokens
send_request() {
    local base_url="$1" api_key="$2" model="$3" provider_name="$4" output_file="$5"
    local messages_json="$6" max_tokens="$7"

    if [ "$provider_name" = "ollama" ]; then
        send_stream_ollama "$base_url" "$model" "$messages_json" "$max_tokens" "$output_file" "$provider_name"
    else
        send_stream_sse "$base_url" "$api_key" "$model" "$messages_json" "$max_tokens" "$output_file" "$provider_name"
    fi
}

# ---- 追加元数据到 metrics JSON ----
append_metadata() {
    local output_file="$1" mem_before="$2" mem_after="$3" is_warmup="$4" round_num="$5" cache_json="$6"

    CACHE_JSON="$cache_json" python3 -c "
import json, os
with open('$output_file') as f:
    d = json.load(f)
d['memory_before_mb'] = int('${mem_before:-0}' or '0')
d['memory_after_mb'] = int('${mem_after:-0}' or '0')
d['is_warmup'] = $is_warmup
d['round'] = $round_num
try:
    d['cache'] = json.loads(os.environ.get('CACHE_JSON', '{}'))
except:
    d['cache'] = {'error': 'parse_failed'}
with open('$output_file', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
}

# ---- 打印轮次结果 ----
print_round_result() {
    local output_file="$1" mem_before="$2" mem_after="$3"
    local ttft tok_s tokens total_ms
    ttft=$(python3 -c "import json; print(json.load(open('$output_file')).get('ttft_ms', '?'))")
    tok_s=$(python3 -c "import json; print(json.load(open('$output_file')).get('decode_tok_s', 0))")
    tokens=$(python3 -c "import json; print(json.load(open('$output_file')).get('tokens_generated', 0))")
    total_ms=$(python3 -c "import json; print(json.load(open('$output_file')).get('total_time_ms', 0))")
    echo "TTFT:${ttft}ms | ${tokens} tok | ${tok_s} tok/s | ${total_ms}ms | mem:${mem_before}→${mem_after}MB"
}

# ---- 构造 messages JSON ----
build_messages() {
    local config_path="$1" prompt_key="${2:-prompt}"
    python3 -c "
import json
p = json.load(open('$config_path'))['$prompt_key']
msgs = []
if p.get('system'):
    msgs.append({'role': 'system', 'content': p['system']})
msgs.append({'role': 'user', 'content': p['user']})
print(json.dumps(msgs))
"
}

# ---- 读取 provider 配置 ----
load_provider() {
    local config_path="$1" idx="$2"
    python3 -c "
import json
p = json.load(open('$config_path'))['providers'][$idx]
print(f'P_NAME=\"{p[\"name\"]}\"')
print(f'P_URL=\"{p[\"base_url\"]}\"')
print(f'P_KEY=\"{p.get(\"api_key\", \"\")}\"')
print(f'P_MODEL=\"{p[\"model\"]}\"')
print(f'P_MANAGED=\"{str(p.get(\"managed\", True)).lower()}\"')
"
}
