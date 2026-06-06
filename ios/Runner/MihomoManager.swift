import Foundation

/// iOS：通过 Network Extension 承载 VPN（mihomo 运行在扩展进程内）
final class MihomoManager {
    static let shared = MihomoManager()

    private(set) var lastStartError: String?

    func resolveBinary() -> String? {
        "network-extension"
    }

    @discardableResult
    func start(configPath: String) -> Bool {
        lastStartError = nil
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        var err: Error?
        Task {
            do {
                ok = try await VpnTunnelManager.shared.start(configPath: configPath)
            } catch {
                err = error
            }
            sem.signal()
        }
        sem.wait()
        if let err {
            lastStartError = err.localizedDescription
            return false
        }
        return ok
    }

    func stop() {
        VpnTunnelManager.shared.stop()
    }

    var isActive: Bool {
        VpnTunnelManager.shared.isActive
    }
}
