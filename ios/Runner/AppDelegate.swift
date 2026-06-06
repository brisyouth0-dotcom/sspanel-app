import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            let messenger = controller.binaryMessenger

            FlutterMethodChannel(name: "com.kele.kele_vpn/vpn", binaryMessenger: messenger)
                .setMethodCallHandler { call, result in
                    switch call.method {
                    case "prepare":
                        Task {
                            do {
                                try await VpnTunnelManager.shared.prepare()
                                result(true)
                            } catch {
                                result(FlutterError(
                                    code: "VPN_PREPARE",
                                    message: error.localizedDescription,
                                    details: nil,
                                ))
                            }
                        }
                    case "start":
                        if let args = call.arguments as? [String: Any],
                           let node = args["nodeName"] as? String {
                            UserDefaults.standard.set(node, forKey: "xinglian_last_vpn_node")
                        }
                        guard let args = call.arguments as? [String: Any],
                              let path = args["configPath"] as? String,
                              !path.isEmpty else {
                            result(FlutterError(
                                code: "VPN_START",
                                message: "缺少 configPath",
                                details: nil,
                            ))
                            return
                        }
                        Task {
                            do {
                                _ = try await VpnTunnelManager.shared.start(configPath: path)
                                result(nil)
                            } catch {
                                result(FlutterError(
                                    code: "VPN_START",
                                    message: error.localizedDescription,
                                    details: nil,
                                ))
                            }
                        }
                    case "stop":
                        VpnTunnelManager.shared.stop()
                        UserDefaults.standard.removeObject(forKey: "xinglian_last_vpn_node")
                        result(nil)
                    case "isActive":
                        result(VpnTunnelManager.shared.isActive)
                    default:
                        result(FlutterMethodNotImplemented)
                    }
                }

            FlutterMethodChannel(name: "com.panlink.vpn/mihomo", binaryMessenger: messenger)
                .setMethodCallHandler { call, result in
                    switch call.method {
                    case "resolveBinary":
                        result(MihomoManager.shared.resolveBinary())
                    case "lastStartError":
                        result(MihomoManager.shared.lastStartError)
                    case "start":
                        guard let args = call.arguments as? [String: Any],
                              let path = args["configPath"] as? String else {
                            result(false)
                            return
                        }
                        result(MihomoManager.shared.start(configPath: path))
                    case "stop":
                        MihomoManager.shared.stop()
                        result(nil)
                    case "getDeviceVpnProfile":
                        result([
                            "kind": "STOCK",
                            "blockQuic": false,
                            "blockDoT": false,
                        ])
                    default:
                        result(FlutterMethodNotImplemented)
                    }
                }

            FlutterMethodChannel(name: "com.kele.kele_vpn/app_disguise", binaryMessenger: messenger)
                .setMethodCallHandler { call, result in
                    switch call.method {
                    case "current":
                        result(DisguiseManager.shared.current())
                    case "apply":
                        let id = (call.arguments as? [String: Any])?["id"] as? String ?? "original"
                        DisguiseManager.shared.apply(id: id) { ok in result(ok) }
                    default:
                        result(FlutterMethodNotImplemented)
                    }
                }

            FlutterMethodChannel(name: "com.kele.kele_vpn/ios_export", binaryMessenger: messenger)
                .setMethodCallHandler { call, result in
                    switch call.method {
                    case "copyText":
                        guard let args = call.arguments as? [String: Any],
                              let text = args["text"] as? String else {
                            result(false)
                            return
                        }
                        UIPasteboard.general.string = text
                        result(true)
                    case "openUrl":
                        guard let args = call.arguments as? [String: Any],
                              let urlStr = args["url"] as? String,
                              let url = URL(string: urlStr) else {
                            result(false)
                            return
                        }
                        UIApplication.shared.open(url, options: [:]) { ok in
                            result(ok)
                        }
                    default:
                        result(FlutterMethodNotImplemented)
                    }
                }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
