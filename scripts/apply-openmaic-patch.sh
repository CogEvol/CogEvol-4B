#!/usr/bin/env bash
# Apply the CogEvol-4B on-device patch to an OpenMAIC (openmaic-live) checkout
# and write the local-inference .env if absent.
#
# Usage: ./apply-openmaic-patch.sh /path/to/openmaic-live
set -e
APP="${1:?usage: apply-openmaic-patch.sh /path/to/openmaic-live}"
[ -f "$APP/package.json" ] || { echo "$APP does not look like the openmaic-live app root (no package.json)"; exit 1; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$HERE/patches/openmaic-live/openmaic-live-offline-on-device.patch"

cd "$APP"
if git apply --check "$PATCH" 2>/dev/null; then
  git apply "$PATCH"
elif patch -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
  patch -p1 < "$PATCH"
else
  echo "❌ patch does not apply cleanly — your checkout is not the validated base."
  echo "   Validated against the openmaic-live app build at commit 667c6af7 (2026-07-22)."
  echo "   The public THU-MAIC/OpenMAIC repo restructured in Aug 2026 and is NOT that base:"
  echo "   for the stock public app use the no-patch .env.local path (README §7 Path A);"
  echo "   see README §7 Path B for the full compatibility note."
  exit 1
fi
echo "[patch] ✅ applied: brief expander + offline asset rewriting + local-demo quota unlock"

# Local inference env — never overwrite an existing .env
if [ ! -f "$APP/.env" ]; then
  cat > "$APP/.env" <<'EOF'
# CogEvol-4B local inference via llama-server (start scripts/serve.sh first)
OLLAMA_BASE_URL=http://127.0.0.1:8081/v1
OLLAMA_MODELS=cogevol-4b-q4_k_m
DEFAULT_MODEL=ollama:cogevol-4b-q4_k_m
EOF
  echo "[patch] ✅ wrote $APP/.env (pointing at 127.0.0.1:8081)"
else
  echo "[patch] ℹ️  $APP/.env exists — make sure OLLAMA_BASE_URL/MODELS/DEFAULT_MODEL are set as in README §4"
fi

echo "next steps:"
echo "  1. ./scripts/fetch-offline-assets.sh $APP   # mirror katex/tailwind/codemirror for offline use"
echo "  2. cd $APP && pnpm install && pnpm build"
echo "  3. cd $APP && pnpm start --port 3200"
