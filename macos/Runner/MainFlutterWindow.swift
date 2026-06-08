import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.isReleasedWhenClosed = false
    self.delegate = self
    if let delegate = NSApp.delegate as? AppDelegate {
      delegate.trayMainWindow = self
    }

    // 默认手机竖屏宽度（390 × 844）
    let phoneWidth: CGFloat = 390
    let phoneHeight: CGFloat = 844
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let originX = screenFrame.midX - phoneWidth / 2
    let originY = screenFrame.midY - phoneHeight / 2
    let frame = NSRect(x: originX, y: originY, width: phoneWidth, height: phoneHeight)
    self.setFrame(frame, display: true)
    self.minSize = NSSize(width: 360, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.kele.kele_vpn/vpn",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "prepare":
        result(true)
      case "start":
        if let args = call.arguments as? [String: Any],
           let node = args["nodeName"] as? String {
          UserDefaults.standard.set(node, forKey: "xinglian_last_vpn_node")
        }
        result(nil)
      case "stop":
        UserDefaults.standard.removeObject(forKey: "xinglian_last_vpn_node")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let mihomoChannel = FlutterMethodChannel(
      name: "com.panlink.vpn/mihomo",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    mihomoChannel.setMethodCallHandler { call, result in
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let proxyChannel = FlutterMethodChannel(
      name: "com.panlink.vpn/system_proxy",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    proxyChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "enable":
        guard let args = call.arguments as? [String: Any],
              let host = args["host"] as? String,
              let port = args["port"] as? Int else {
          result(false)
          return
        }
        result(SystemProxyManager.shared.enable(host: host, port: port))
      case "disable":
        result(SystemProxyManager.shared.disable())
      case "isEnabled":
        result(SystemProxyManager.shared.isEnabled())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let menuBarChannel = FlutterMethodChannel(
      name: "com.panlink.vpn/menu_bar",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    StatusBarManager.shared.configure(
      messenger: flutterViewController.engine.binaryMessenger
    )
    menuBarChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "updateMenu":
        guard let args = call.arguments as? [String: Any] else {
          result(nil)
          return
        }
        let connected = args["connected"] as? Bool ?? false
        let nodeName = args["nodeName"] as? String
        let mode = args["mode"] as? String
        let selectedNodeId = args["selectedNodeId"] as? String
        let autoSelectActive = args["autoSelectActive"] as? Bool ?? false
        let nodesRaw = args["nodes"] as? [[String: Any]] ?? []
        let nodes = nodesRaw.map { entry -> [String: String] in
          [
            "id": entry["id"] as? String ?? "",
            "name": entry["name"] as? String ?? "",
          ]
        }
        StatusBarManager.shared.updateMenu(
          connected: connected,
          nodeName: nodeName,
          mode: mode,
          nodes: nodes,
          selectedNodeId: selectedNodeId,
          autoSelectActive: autoSelectActive
        )
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }
}
