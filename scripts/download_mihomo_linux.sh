#!/usr/bin/env bash
set -euo pipefail
VERSION="${MIHOMO_VERSION:-v1.19.26}"
ASSET="mihomo-linux-amd64-${VERSION}.gz"
URL="https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/${ASSET}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/linux/runner/resources"
mkdir -p "$OUT"
TMP="$(mktemp).gz"
echo "Downloading ${URL}"
curl -fL --retry 5 -o "$TMP" "$URL"
gunzip -c "$TMP" > "$OUT/mihomo"
chmod +x "$OUT/mihomo"
rm -f "$TMP"
file "$OUT/mihomo"
