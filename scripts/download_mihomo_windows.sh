#!/usr/bin/env bash
set -euo pipefail
VERSION="${MIHOMO_VERSION:-v1.19.26}"
# compatible 构建在虚拟机/旧 CPU 上更稳定；标准 amd64 在部分环境会 0xC0000005 崩溃
ASSET="mihomo-windows-amd64-compatible-${VERSION}.zip"
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
