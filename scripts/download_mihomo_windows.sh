#!/usr/bin/env bash
set -euo pipefail
VERSION="${MIHOMO_VERSION:-v1.19.26}"
ASSET="mihomo-windows-amd64-${VERSION}.zip"
URL="https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/${ASSET}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/windows/runner/resources"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
echo "Downloading ${URL}"
curl -fL --retry 5 -o "$TMP/mihomo.zip" "$URL"
unzip -o "$TMP/mihomo.zip" -d "$TMP"
find "$TMP" -name "mihomo*.exe" -exec cp {} "$OUT/mihomo.exe" \;
chmod +x "$OUT/mihomo.exe" 2>/dev/null || true
rm -rf "$TMP"
ls -lh "$OUT/mihomo.exe"
