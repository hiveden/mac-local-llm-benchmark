#!/bin/bash
# 自动采集硬件/软件环境信息
# 输出 JSON 到 stdout

set -euo pipefail

get_version() {
    local cmd="$1"
    local flag="${2:---version}"
    if command -v "$cmd" &>/dev/null; then
        $cmd $flag 2>&1 | head -1
    else
        echo "not installed"
    fi
}

cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hardware": {
    "chip": "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')",
    "cores_total": $(sysctl -n hw.ncpu),
    "memory_gb": $(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1024/1024/1024}'),
    "os": "$(sw_vers -productName) $(sw_vers -productVersion)"
  },
  "software": {
    "ollama": "$(get_version ollama --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')",
    "omlx": "$(brew list --versions omlx 2>/dev/null | awk '{print $2}' || echo 'not installed')",
    "mlx_lm": "$(python3 -c 'import mlx_lm; print(mlx_lm.__version__)' 2>/dev/null || echo 'not installed')",
    "python": "$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')",
    "node": "$(node --version 2>/dev/null || echo 'not installed')"
  }
}
EOF
