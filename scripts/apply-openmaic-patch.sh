#!/usr/bin/env bash
# Apply the CogEvol-4B on-device patch to an OpenMAIC checkout and write the
# local-inference .env.local if absent.
#
# Usage: ./apply-openmaic-patch.sh /path/to/OpenMAIC
#
# The patch is validated against public OpenMAIC commit f6cf8fd4 (2026-08-30).
# If your checkout is newer and the patch no longer applies, either
#   git checkout f6cf8fd4   (in the OpenMAIC repo)
# or rebase the patch by hand — it touches 10 files and is mostly additive.
set -e
APP="${1:?usage: apply-openmaic-patch.sh /path/to/OpenMAIC}"
[ -f "$APP/package.json" ] || { echo "$APP does not look like the OpenMAIC app root (no package.json)"; exit 1; }
[ -d "$APP/packages/@openmaic/generation" ] || { echo "$APP does not look like the current OpenMAIC layout (packages/@openmaic/generation missing)"; exit 1; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$HERE/patches/openmaic/openmaic-offline-on-device.patch"

cd "$APP"
if git apply --check "$PATCH" 2>/dev/null; then
  git apply "$PATCH"
elif patch -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
  patch -p1 < "$PATCH"
else
  echo "❌ patch does not apply cleanly — your checkout has moved past the validated base."
  echo "   Validated against public OpenMAIC commit f6cf8fd4 (2026-08-30)."
  echo "   Either: git checkout f6cf8fd4"
  echo "   Or rebase the patch by hand (10 files, mostly additive) — see patches/openmaic/."
  exit 1
fi
echo "[patch] ✅ applied: brief expander (opt-in via courseContext) + offline asset rewriting"

# Local inference env — never overwrite an existing env file
if [ ! -f "$APP/.env.local" ] && [ ! -f "$APP/.env" ]; then
  cat > "$APP/.env.local" <<'EOF'
# CogEvol-4B local inference via llama-server (start scripts/serve.sh first)
OLLAMA_BASE_URL=http://127.0.0.1:8081/v1
OLLAMA_MODELS=cogevol-4b-q4_k_m
DEFAULT_MODEL=ollama:cogevol-4b-q4_k_m
EOF
  echo "[patch] ✅ wrote $APP/.env.local (pointing at 127.0.0.1:8081)"
else
  echo "[patch] ℹ️  env file exists — make sure OLLAMA_BASE_URL/MODELS/DEFAULT_MODEL are set as in README §7"
fi

echo "next steps:"
echo "  1. ./scripts/fetch-offline-assets.sh $APP   # mirror katex/tailwind/codemirror for offline use"
echo "  2. cd $APP && pnpm install && pnpm build"
echo "  3. cd $APP && pnpm start -- -p 3200"
