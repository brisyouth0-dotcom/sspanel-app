#!/usr/bin/env bash
# 让 Gradle/JVM 使用系统或本地代理，避免国内直连 Maven 时 TLS 握手失败。
# 用法: source scripts/gradle_proxy_env.sh

gradle_proxy_apply() {
  local host="" port=""

  if [[ -n "${HTTP_PROXY:-}" || -n "${http_proxy:-}" ]]; then
    local proxy="${HTTP_PROXY:-${http_proxy:-}}"
    if [[ "$proxy" =~ ^https?://([^:/]+):?([0-9]*) ]]; then
      host="${BASH_REMATCH[1]}"
      port="${BASH_REMATCH[2]:-7890}"
    fi
  elif command -v scutil >/dev/null 2>&1; then
    local enabled host_line port_line
    enabled="$(scutil --proxy 2>/dev/null | awk -F': ' '/HTTPSEnable|HTTPEnable/{print $2}' | head -1)"
    host_line="$(scutil --proxy 2>/dev/null | awk -F': ' '/HTTPSProxy|HTTPProxy/{print $2; exit}')"
    port_line="$(scutil --proxy 2>/dev/null | awk -F': ' '/HTTPSPort|HTTPPort/{print $2; exit}')"
    if [[ "$enabled" == "1" && -n "$host_line" ]]; then
      host="$host_line"
      port="${port_line:-7890}"
    fi
  fi

  if [[ -z "$host" ]]; then
    return 0
  fi

  export GRADLE_OPTS="${GRADLE_OPTS:-} -Djava.net.useSystemProxies=true -Dhttp.proxyHost=${host} -Dhttp.proxyPort=${port} -Dhttps.proxyHost=${host} -Dhttps.proxyPort=${port}"
  echo "[gradle] 使用代理 ${host}:${port} 下载依赖"
}

gradle_proxy_apply
