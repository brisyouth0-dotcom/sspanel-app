#!/usr/bin/env bash
# 构建 iOS 用 Libmihomo.xcframework（需 Go 1.22+、gomobile、Xcode）
# 参考 proxycat / sing-box-for-apple 的 gomobile 绑定方式。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/ios/Frameworks"
FRAMEWORK="${OUT_DIR}/Libmihomo.xcframework"
VERSION="${MIHOMO_VERSION:-v1.19.26}"
WORK="${ROOT}/.tmp/mihomo-ios-build"

if ! command -v go >/dev/null 2>&1; then
  echo "请先安装 Go: https://go.dev/dl/"
  exit 1
fi

mkdir -p "$OUT_DIR" "$WORK"
cd "$WORK"

if [[ ! -d mihomo ]]; then
  git clone --depth 1 --branch "$VERSION" https://github.com/MetaCubeX/mihomo.git 2>/dev/null \
    || git clone --depth 1 https://github.com/MetaCubeX/mihomo.git
fi

cd mihomo
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
export PATH="$(go env GOPATH)/bin:$PATH"
gomobile init

# 最小绑定包：需在 mihomo 仓库内补充 mobile 入口（与 proxycat 类似）
# 若官方无 mobile 包，请从 https://github.com/MMitsuha/proxycat 复制 binding 目录后重试。
if [[ ! -d mobile ]]; then
  cat <<'EOF'

⚠️  mihomo 官方仓库暂无 iOS mobile 绑定。

请任选其一：
  1. 从 proxycat 项目复制 binding/ 与 Libmihomo 构建脚本到本仓库 ios/mihomo-mobile/
  2. 使用已构建的 Libmihomo.xcframework 放入 ios/Frameworks/

完成后在 Xcode 中为 Runner 与 VpnExtension 添加：
  - Framework Search Paths: $(PROJECT_DIR)/Frameworks
  - Other Swift Flags: -DMIHOMO_EMBEDDED
  - 链接 Libmihomo.xcframework

并在 Apple Developer 后台为 App ID 开启 Network Extension (Packet Tunnel) 能力。

EOF
  exit 1
fi

gomobile bind -target=ios -o "$FRAMEWORK" ./mobile
echo "✅ 已生成 $FRAMEWORK"
ls -lh "$FRAMEWORK"
