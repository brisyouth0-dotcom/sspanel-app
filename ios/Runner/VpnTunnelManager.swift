import Foundation
import NetworkExtension

enum VpnTunnelError: LocalizedError {
    case saveFailed(String)
    case sessionUnavailable
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let msg): return msg
        case .sessionUnavailable: return "VPN 会话不可用"
        case .startFailed(let msg): return msg
        }
    }
}

/// 通过 NETunnelProviderManager 启停 Packet Tunnel Extension
final class VpnTunnelManager {
    static let shared = VpnTunnelManager()

    private let manager = NETunnelProviderManager.shared()

    private init() {}

    func prepare() async throws {
        try await manager.loadFromPreferences()
        let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
        if proto == nil || proto?.providerBundleIdentifier != VpnConstants.extensionBundleId {
            let tunnel = NETunnelProviderProtocol()
            tunnel.providerBundleIdentifier = VpnConstants.extensionBundleId
            tunnel.serverAddress = "灵猫加速器"
            manager.protocolConfiguration = tunnel
            manager.localizedDescription = "灵猫加速器"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } else if !manager.isEnabled {
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        }
    }

    @discardableResult
    func start(configPath: String) async throws -> Bool {
        try await prepare()
        guard let dest = VpnConstants.sharedConfigURL else {
            throw VpnTunnelError.startFailed("App Group 未配置，请在 Xcode 中启用 group.com.kele.keleVpn")
        }
        let src = URL(fileURLWithPath: configPath)
        if !FileManager.default.fileExists(atPath: src.path) {
            throw VpnTunnelError.startFailed("配置文件不存在")
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)

        guard let session = manager.connection as? NETunnelProviderSession else {
            throw VpnTunnelError.sessionUnavailable
        }
        let options: [String: NSObject] = [
            "configPath": dest.path as NSString,
        ]
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try session.startTunnel(options: options)
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }
        return true
    }

    func stop() {
        manager.connection.stopVPNTunnel()
    }

    var isActive: Bool {
        switch manager.connection.status {
        case .connected, .connecting, .reasserting:
            return true
        default:
            return false
        }
    }

    var statusDescription: String {
        switch manager.connection.status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }
}
