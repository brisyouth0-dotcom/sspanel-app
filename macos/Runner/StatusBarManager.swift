import Cocoa
import FlutterMacOS

/// macOS 顶部菜单栏托盘（类似 Clash Verge）
final class StatusBarManager: NSObject {
  static let shared = StatusBarManager()

  private var statusItem: NSStatusItem?
  private weak var messenger: FlutterBinaryMessenger?
  private var connected = false
  private var nodeName = ""
  private var mode = "rule"
  private var nodes: [[String: String]] = []
  private var selectedNodeId = ""

  func configure(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    installStatusItemIfNeeded()
    rebuildMenu()
  }

  func updateMenu(
    connected: Bool,
    nodeName: String?,
    mode: String?,
    nodes: [[String: String]]?,
    selectedNodeId: String?
  ) {
    self.connected = connected
    self.nodeName = nodeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.mode = mode ?? "rule"
    self.nodes = nodes ?? []
    self.selectedNodeId = selectedNodeId ?? ""
    installStatusItemIfNeeded()
    rebuildMenu()
    updateButtonAppearance()
  }

  private func installStatusItemIfNeeded() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      button.image = statusImage()
      button.imagePosition = .imageOnly
      button.toolTip = "灵猫加速器"
    }
    statusItem = item
  }

  private func statusImage() -> NSImage? {
    if let icon = NSApp.applicationIconImage {
      icon.size = NSSize(width: 18, height: 18)
      return icon
    }
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let icon = NSImage(contentsOf: url) {
      icon.size = NSSize(width: 18, height: 18)
      return icon
    }
    if #available(macOS 11.0, *) {
      return NSImage(systemSymbolName: "network", accessibilityDescription: "灵猫加速器")
    }
    return nil
  }

  private func updateButtonAppearance() {
    guard let button = statusItem?.button else { return }
    button.alphaValue = connected ? 1.0 : 0.55
    if connected, !nodeName.isEmpty {
      button.toolTip = "灵猫加速器 · 已连接 · \(nodeName)"
    } else if connected {
      button.toolTip = "灵猫加速器 · 已连接"
    } else {
      button.toolTip = "灵猫加速器 · 未连接"
    }
  }

  private func rebuildMenu() {
    guard let item = statusItem else { return }
    let menu = NSMenu()

    let showItem = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
    showItem.target = self
    menu.addItem(showItem)

    let toggleTitle = connected ? "断开连接" : "连接"
    let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleConnection), keyEquivalent: "")
    toggleItem.target = self
    menu.addItem(toggleItem)

    menu.addItem(.separator())

    addModeItem(menu, title: "规则", mode: "rule")
    addModeItem(menu, title: "全局", mode: "global")
    addModeItem(menu, title: "直连", mode: "direct")

    menu.addItem(.separator())

    let nodeMenu = NSMenu()
    if nodes.isEmpty {
      let emptyItem = NSMenuItem(title: "暂无节点", action: nil, keyEquivalent: "")
      emptyItem.isEnabled = false
      nodeMenu.addItem(emptyItem)
    } else {
      for entry in nodes {
        let id = entry["id"] ?? ""
        let name = entry["name"] ?? id
        let nodeItem = NSMenuItem(title: name, action: #selector(selectNode(_:)), keyEquivalent: "")
        nodeItem.target = self
        nodeItem.representedObject = id
        if id == selectedNodeId {
          nodeItem.state = .on
        }
        nodeMenu.addItem(nodeItem)
      }
    }
    let nodeRoot = NSMenuItem(title: "🚀 节点选择", action: nil, keyEquivalent: "")
    nodeRoot.submenu = nodeMenu
    menu.addItem(nodeRoot)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    item.menu = menu
  }

  private func addModeItem(_ menu: NSMenu, title: String, mode: String) {
    let item = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = mode
    if self.mode == mode {
      item.state = .on
    }
    menu.addItem(item)
  }

  @objc private func showMainWindow() {
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      if let delegate = NSApp.delegate as? AppDelegate {
        delegate.showMainWindow()
        return
      }
      for window in NSApp.windows where window.canBecomeMain {
        window.makeKeyAndOrderFront(nil)
        return
      }
    }
  }

  @objc private func toggleConnection() {
    invokeFlutter(action: "toggleConnection")
    showMainWindow()
  }

  @objc private func setMode(_ sender: NSMenuItem) {
    guard let mode = sender.representedObject as? String else { return }
    invokeFlutter(action: "setMode", extra: ["mode": mode])
  }

  @objc private func selectNode(_ sender: NSMenuItem) {
    guard let nodeId = sender.representedObject as? String, !nodeId.isEmpty else { return }
    invokeFlutter(action: "selectNode", extra: ["nodeId": nodeId])
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  private func invokeFlutter(action: String, extra: [String: Any] = [:]) {
    guard let messenger else { return }
    var args: [String: Any] = ["action": action]
    for (key, value) in extra {
      args[key] = value
    }
    let channel = FlutterMethodChannel(
      name: "com.panlink.vpn/menu_bar",
      binaryMessenger: messenger
    )
    channel.invokeMethod("menuAction", arguments: args)
  }
}
