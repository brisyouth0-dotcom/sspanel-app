import Cocoa
import FlutterMacOS

/// 在应用内 fork 并管理 mihomo 子进程
final class MihomoManager {
  static let shared = MihomoManager()

  private var process: Process?
  private(set) var lastStartError: String?

  func resolveBinary() -> String? {
    if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
      let macOSBinary = execDir.appendingPathComponent("mihomo").path
      if FileManager.default.isExecutableFile(atPath: macOSBinary) {
        return macOSBinary
      }
    }
    if let bundled = Bundle.main.path(forResource: "mihomo", ofType: nil),
       FileManager.default.isExecutableFile(atPath: bundled) {
      return bundled
    }
    let fm = FileManager.default
    var candidates = [
      "/opt/homebrew/bin/mihomo",
      "/usr/local/bin/mihomo",
      "\(NSHomeDirectory())/bin/mihomo",
      "\(NSHomeDirectory())/.local/bin/mihomo",
      "\(fm.currentDirectoryPath)/mihomo",
    ]
    if let resourcePath = Bundle.main.resourcePath {
      candidates.append("\(resourcePath)/mihomo")
    }
    if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let bundleId = Bundle.main.bundleIdentifier ?? "xinglian_vpn"
      candidates.append(support.appendingPathComponent(bundleId).appendingPathComponent("mihomo/mihomo").path)
      candidates.append(support.appendingPathComponent("xinglian_vpn/mihomo/mihomo").path)
      candidates.append(support.appendingPathComponent("mihomo/mihomo").path)
    }
    for path in candidates where fm.isExecutableFile(atPath: path) {
      return path
    }
    return nil
  }

  @discardableResult
  func start(configPath: String) -> Bool {
    stop()
    lastStartError = nil
    guard let binary = resolveBinary() else {
      lastStartError = "未找到 mihomo 可执行文件"
      return false
    }
    let workDir = (configPath as NSString).deletingLastPathComponent
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: binary)
    proc.arguments = ["-d", workDir, "-f", configPath]
    proc.currentDirectoryURL = URL(fileURLWithPath: workDir)
    var env = ProcessInfo.processInfo.environment
    env["CLASH_OVERRIDE_EXTERNAL_CONTROLLER"] =
      "\(ProcessInfo.processInfo.environment["MIHOMO_CONTROLLER"] ?? "127.0.0.1:9090")"
    proc.environment = env
    let errPipe = Pipe()
    proc.standardError = errPipe
    proc.standardOutput = FileHandle.nullDevice
    do {
      try proc.run()
      Thread.sleep(forTimeInterval: 0.5)
      if proc.isRunning {
        process = proc
        return true
      }
      let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
      let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
      lastStartError = errText?.isEmpty == false ? errText : "mihomo 进程已退出（code \(proc.terminationStatus)）"
      return false
    } catch {
      lastStartError = "启动失败：\(error.localizedDescription)"
      return false
    }
  }

  func stop() {
    guard let proc = process else { return }
    if proc.isRunning {
      proc.terminate()
      proc.waitUntilExit()
    }
    process = nil
  }
}
