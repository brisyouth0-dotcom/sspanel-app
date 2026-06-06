#!/usr/bin/env bash
# 从 sockstun 发布包提取 hev-socks5-tunnel 预编译库（MIT）
set -euo pipefail
VERSION="${SOCKSTUN_VERSION:-7.0}"
APK="hev.sockstun-${VERSION}-release.apk"
URL="https://github.com/heiher/sockstun/releases/download/${VERSION}/${APK}"
JNI_ROOT="$(cd "$(dirname "$0")/.." && pwd)/android/app/src/main/jniLibs"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading ${URL} ..."
curl -fL --retry 5 --retry-delay 3 -o "${TMP}/${APK}" "$URL"

for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  mkdir -p "${JNI_ROOT}/${abi}"
  unzip -p "${TMP}/${APK}" "lib/${abi}/libhev-socks5-tunnel.so" \
    > "${JNI_ROOT}/${abi}/libhev-socks5-tunnel.so"
  chmod 644 "${JNI_ROOT}/${abi}/libhev-socks5-tunnel.so"
  ls -lh "${JNI_ROOT}/${abi}/libhev-socks5-tunnel.so"
done
echo "hev-socks5-tunnel installed."
