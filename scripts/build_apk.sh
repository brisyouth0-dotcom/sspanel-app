#!/usr/bin/env bash
# 使用官方 Flutter 存储 + 自动配置 Gradle 代理，避免 TLS 握手失败
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com/download.flutter.io"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"

# Gradle/JVM 走本机代理（如 Clash 7890），否则 Maven 直连常握手失败
# shellcheck source=scripts/gradle_proxy_env.sh
source "$ROOT/scripts/gradle_proxy_env.sh"

exec flutter build apk --release "$@"
