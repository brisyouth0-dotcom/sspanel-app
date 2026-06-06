import Foundation

/// 通过 networksetup 设置 / 恢复 macOS 系统代理
final class SystemProxyManager {
  static let shared = SystemProxyManager()

  private struct ProxyBackup {
    let service: String
    let webOn: Bool
    let webHost: String
    let webPort: String
    let secureOn: Bool
    let secureHost: String
    let securePort: String
    let socksOn: Bool
    let socksHost: String
    let socksPort: String
  }

  private var backups: [ProxyBackup] = []
  private(set) var active = false

  private func runNetworkSetup(_ args: [String]) -> (status: Int32, output: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    do {
      try task.run()
      task.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      return (task.terminationStatus, output)
    } catch {
      return (-1, error.localizedDescription)
    }
  }

  private func networkServices() -> [String] {
    let (_, output) = runNetworkSetup(["-listallnetworkservices"])
    return output
      .components(separatedBy: "\n")
      .dropFirst()
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { line in
        !line.isEmpty &&
          !line.hasPrefix("An asterisk") &&
          !line.hasPrefix("*") &&
          !line.hasPrefix("（")
      }
  }

  private struct ProxyState {
    var enabled = false
    var host = ""
    var port = ""
  }

  private func readProxy(_ type: String, service: String) -> ProxyState {
    let (_, output) = runNetworkSetup(["-\(type)", service])
    var state = ProxyState()
    for line in output.components(separatedBy: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      if t.hasPrefix("Enabled:") {
        state.enabled = t.contains("Yes")
      } else if t.hasPrefix("Server:") {
        state.host = t.replacingOccurrences(of: "Server:", with: "")
          .trimmingCharacters(in: .whitespaces)
      } else if t.hasPrefix("Port:") {
        state.port = t.replacingOccurrences(of: "Port:", with: "")
          .trimmingCharacters(in: .whitespaces)
      }
    }
    return state
  }

  @discardableResult
  func enable(host: String, port: Int) -> Bool {
    backups.removeAll()
    let portStr = "\(port)"
    var ok = true

    for service in networkServices() {
      let web = readProxy("getwebproxy", service: service)
      let secure = readProxy("getsecurewebproxy", service: service)
      let socks = readProxy("getsocksfirewallproxy", service: service)

      backups.append(
        ProxyBackup(
          service: service,
          webOn: web.enabled,
          webHost: web.host,
          webPort: web.port,
          secureOn: secure.enabled,
          secureHost: secure.host,
          securePort: secure.port,
          socksOn: socks.enabled,
          socksHost: socks.host,
          socksPort: socks.port
        )
      )

      ok = runNetworkSetup(["-setwebproxy", service, host, portStr]).status == 0 && ok
      ok = runNetworkSetup(["-setsecurewebproxy", service, host, portStr]).status == 0 && ok
      ok = runNetworkSetup(["-setsocksfirewallproxy", service, host, portStr]).status == 0 && ok
      ok = runNetworkSetup(["-setwebproxystate", service, "on"]).status == 0 && ok
      ok = runNetworkSetup(["-setsecurewebproxystate", service, "on"]).status == 0 && ok
      ok = runNetworkSetup(["-setsocksfirewallproxystate", service, "on"]).status == 0 && ok
    }

    active = ok
    return ok
  }

  @discardableResult
  func disable() -> Bool {
    var ok = true

    if backups.isEmpty {
      for service in networkServices() {
        ok = runNetworkSetup(["-setwebproxystate", service, "off"]).status == 0 && ok
        ok = runNetworkSetup(["-setsecurewebproxystate", service, "off"]).status == 0 && ok
        ok = runNetworkSetup(["-setsocksfirewallproxystate", service, "off"]).status == 0 && ok
      }
    } else {
      for backup in backups {
        restoreProxy(
          service: backup.service,
          type: "web",
          on: backup.webOn,
          host: backup.webHost,
          port: backup.webPort
        )
        restoreProxy(
          service: backup.service,
          type: "secureweb",
          on: backup.secureOn,
          host: backup.secureHost,
          port: backup.securePort
        )
        restoreProxy(
          service: backup.service,
          type: "socksfirewall",
          on: backup.socksOn,
          host: backup.socksHost,
          port: backup.socksPort
        )
      }
      backups.removeAll()
    }

    active = false
    return ok
  }

  private func restoreProxy(
    service: String,
    type: String,
    on: Bool,
    host: String,
    port: String
  ) {
    if on, !host.isEmpty, !port.isEmpty {
      _ = runNetworkSetup(["-set\(type)proxy", service, host, port])
      _ = runNetworkSetup(["-set\(type)proxystate", service, "on"])
    } else {
      _ = runNetworkSetup(["-set\(type)proxystate", service, "off"])
    }
  }

  func isEnabled() -> Bool {
    active
  }
}
