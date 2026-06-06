import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  weak var trayMainWindow: NSWindow?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭窗口后保留菜单栏托盘，便于后台代理
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    guard let window = trayMainWindow else {
      for window in NSApp.windows where window.canBecomeMain {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return
      }
      return
    }
    if !window.isVisible {
      window.setIsVisible(true)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }
}
