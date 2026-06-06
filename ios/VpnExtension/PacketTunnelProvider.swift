import NetworkExtension
import os.log

/// Packet Tunnel：在扩展进程内运行 mihomo（需先执行 scripts/build_mihomo_ios.sh 嵌入 Libmihomo.xcframework）
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: VpnConstants.extensionBundleId, category: "Tunnel")

    override func startTunnel(options: [String: NSObject]?) async throws {
        logger.info("startTunnel")
        let configPath = (options?["configPath"] as? String)
            ?? VpnConstants.sharedConfigURL?.path
        guard let configPath, FileManager.default.fileExists(atPath: configPath) else {
            throw NSError(
                domain: "VpnExtension",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "找不到 VPN 配置文件"],
            )
        }

        try await applyTunnelNetworkSettings()

        #if MIHOMO_EMBEDDED
        let fd = try packetFlowFileDescriptor()
        try MihomoEmbeddedBridge.start(configPath: configPath, tunFd: fd)
        logger.info("mihomo started in extension")
        #else
        throw NSError(
            domain: "VpnExtension",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "iOS 内核未嵌入。请在 Mac 上执行 ./scripts/build_mihomo_ios.sh，并用 Xcode 重新编译安装。",
            ],
        )
        #endif
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void,
    ) {
        #if MIHOMO_EMBEDDED
        MihomoEmbeddedBridge.stop()
        #endif
        completionHandler()
    }

    private func applyTunnelNetworkSettings() async throws {
        let settings = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: VpnConstants.tunnelRemoteAddress,
        )
        let ipv4 = NEIPv4Settings(
            addresses: [VpnConstants.tunnelClientAddress],
            subnetMasks: [VpnConstants.tunnelSubnetMask],
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: [VpnConstants.virtualDns])
        settings.mtu = NSNumber(value: VpnConstants.tunnelMtu)
        try await setTunnelNetworkSettings(settings)
    }

    /// 从 NEPacketTunnelFlow 获取 utun fd（不同 iOS 版本 KVC 路径不同）
    private func packetFlowFileDescriptor() throws -> Int32 {
        let flow = self.packetFlow
        let keys = ["socket.fileDescriptor", "socketFD", "fd"]
        for key in keys {
            if let n = flow.value(forKeyPath: key) as? NSNumber {
                return n.int32Value
            }
        }
        throw NSError(
            domain: "VpnExtension",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "无法获取 TUN 文件描述符"],
        )
    }
}

#if MIHOMO_EMBEDDED
/// 由 build_mihomo_ios.sh 生成的 Libmihomo 桥接；此处为编译占位
enum MihomoEmbeddedBridge {
    static func start(configPath: String, tunFd: Int32) throws {
        // Libmihomo.Start(configPath, tunFd) — 由 xcframework 提供
    }

    static func stop() {
        // Libmihomo.Stop()
    }
}
#endif
