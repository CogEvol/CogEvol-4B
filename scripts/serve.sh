#!/usr/bin/env bash
# CogEvol-4B (Q4_K_M) local inference server — llama.cpp + OpenAI-compatible API.
#
# Usage:
#   ./serve.sh /path/to/cogevol-4b-q4_k_m.gguf [port]
# Env:
#   LLAMA_SERVER   path to llama-server binary (default: first in PATH)
#   CTX            context size (default 32768; HTML generation needs >= 24576)
#
# Flags explained (see README §6 for the full table):
#   --jinja                        enable chat-template handling (tool args / template kwargs)
#   --chat-template-kwargs '...'   disable Qwen-style thinking — REQUIRED, see README §6/§10
#   -ngl 99                        offload all layers to GPU (Metal on Apple Silicon)
#   --temp 0                       deterministic output (matches our published evals)
#   -fa auto                       flash attention
set -u
export no_proxy="127.0.0.1,localhost" NO_PROXY="127.0.0.1,localhost"

MODEL="${1:-${MODEL:-./cogevol-4b-q4_k_m.gguf}}"
PORT="${2:-8081}"
CTX="${CTX:-32768}"
SERVER="${LLAMA_SERVER:-$(command -v llama-server || true)}"
if [ -z "$SERVER" ] || [ ! -x "$SERVER" ]; then
  for cand in "$HOME/.local/bin/llama-server" /opt/homebrew/bin/llama-server /usr/local/bin/llama-server; do
    if [ -x "$cand" ]; then SERVER="$cand"; break; fi
  done
fi
[ -x "$SERVER" ] || { echo "llama-server not found. Build llama.cpp first (README §2) or set LLAMA_SERVER=/path/to/llama-server"; exit 1; }
[ -f "$MODEL" ] || { echo "Model file not found: $MODEL  (download it first, README §1)"; exit 1; }

wait_ready() {  # $1 = seconds, $2 = pid; health endpoint returns 503 while loading — must check for 200
  for _ in $(seq 1 "$1"); do
    CODE=$(curl --noproxy '*' -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/health" 2>/dev/null || echo 000)
    [ "$CODE" = "200" ] && return 0
    # a crashed launch (e.g. the macOS ≤13 Metal assert) must not burn the full timeout
    if [ -n "${2:-}" ] && ! kill -0 "$2" 2>/dev/null; then
      echo "[serve] process exited during startup — see $LOG"
      return 1
    fi
    sleep 1
  done
  return 1
}

launch() {  # $1 = ngl
  "$SERVER" -m "$MODEL" --port "$PORT" -c "$CTX" -ngl "$1" --temp 0 -fa auto \
    --jinja --chat-template-kwargs '{"enable_thinking": false}' > "$LOG" 2>&1 &
  echo $!
}
LOG="$(dirname "$MODEL")/cogevol-4b-server.log"

echo "[serve] starting llama-server on 127.0.0.1:$PORT (ctx=$CTX)"
echo "[serve] log: $LOG"
PID=$(launch 99)
if wait_ready 300 "$PID"; then
  echo "[serve] ✅ GPU (Metal) ready — pid=$PID port=$PORT"
  echo "[serve] test: curl --noproxy '*' http://127.0.0.1:$PORT/v1/models"
  exit 0
fi
kill "$PID" 2>/dev/null
if grep -q "GGML_ASSERT" "$LOG" 2>/dev/null; then
  echo "[serve] ⚠️ GPU launch crashed (GGML_ASSERT — known macOS ≤13 Metal issue, see patches/llama-cpp/macos13-metal-buffer-fix.md)"
else
  echo "[serve] ⚠️ GPU launch not ready in 300s"
fi
echo "[serve] falling back to CPU (-ngl 0, expect ~20 t/s on laptop-class machines)"
PID=$(launch 0)
if wait_ready 600 "$PID"; then
  echo "[serve] ✅ CPU ready — pid=$PID port=$PORT"
else
  echo "[serve] ❌ failed to start; inspect $LOG"; kill "$PID" 2>/dev/null; exit 1
fi
