import Foundation

enum VpnConstants {
    static let appGroupId = "group.com.kele.keleVpn"
    static let extensionBundleId = "com.kele.keleVpn.VpnExtension"
    static let configFileName = "config.yaml"
    static let tunnelRemoteAddress = "172.19.0.1"
    static let tunnelClientAddress = "172.19.0.1"
    static let tunnelSubnetMask = "255.255.255.252"
    static let virtualDns = "172.19.0.2"
    static let tunnelMtu = 1280

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId,
        )
    }

    static var sharedConfigURL: URL? {
        sharedContainerURL?.appendingPathComponent(configFileName)
    }
}
