#!/usr/bin/env bash
# Mirror the third-party runtime assets that generated interactive widgets
# reference, so the OpenMAIC app works with WiFi switched off.
#
# Usage: ./fetch-offline-assets.sh /path/to/openmaic-live
#
# What it installs into <openmaic-live>/public:
#   /katex/...                       copied from node_modules/katex (exact version the app uses)
#   /libs/tailwind/tailwindcss.js    Tailwind Play CDN runtime (widgets emit <script src="https://cdn.tailwindcss.com">)
#   /libs/codemirror/5.65.12/...     CodeMirror (code widgets)
# The post-processor added by our patch rewrites those CDN URLs to these
# same-origin paths and strips every other external reference.
set -e
APP="${1:?usage: fetch-offline-assets.sh /path/to/openmaic-live}"
[ -d "$APP/node_modules/katex" ] || { echo "katex not installed — run 'pnpm install' in $APP first"; exit 1; }

# 1) KaTeX from local node_modules (no network needed)
mkdir -p "$APP/public/katex/contrib"
cp "$APP/node_modules/katex/dist/katex.min.css" "$APP/public/katex/"
cp "$APP/node_modules/katex/dist/katex.min.js" "$APP/public/katex/"
cp "$APP/node_modules/katex/dist/contrib/auto-render.min.js" "$APP/public/katex/contrib/"
cp -R "$APP/node_modules/katex/dist/fonts" "$APP/public/katex/fonts"
echo "[assets] katex: copied from node_modules"

# 2) Tailwind Play CDN runtime (single file)
mkdir -p "$APP/public/libs/tailwind"
TW="$APP/public/libs/tailwind/tailwindcss.js"
if [ ! -s "$TW" ]; then
  curl -fsSL --max-time 90 https://cdn.tailwindcss.com -o "$TW" \
    || echo "[assets] ⚠️ could not fetch Tailwind runtime — download it on any online machine and scp to $TW"
else
  echo "[assets] tailwind: already present"
fi

# 3) CodeMirror 5.65.12 (lib + python mode + dracula theme)
CM="$APP/public/libs/codemirror/5.65.12"
mkdir -p "$CM/lib" "$CM/mode/python" "$CM/theme"
base="https://cdn.jsdelivr.net/npm/codemirror@5.65.12"
for f in lib/codemirror.min.js lib/codemirror.min.css mode/python/python.min.js theme/dracula.min.css; do
  if [ ! -s "$CM/$f" ]; then
    curl -fsSL --max-time 60 "$base/$f" -o "$CM/$f" \
      || echo "[assets] ⚠️ could not fetch $f — widgets of type 'code' will fall back to a plain textarea"
  fi
done
echo "[assets] codemirror: done"
echo "[assets] ✅ offline assets ready. Rebuild the app if it was already built: (cd $APP && pnpm build)"
