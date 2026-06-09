#include "tray_manager.h"

#include <shellapi.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <mutex>

namespace {

constexpr UINT kTrayCallbackMessage = WM_USER + 101;
constexpr UINT kCmdShow = 40001;
constexpr UINT kCmdToggle = 40002;
constexpr UINT kCmdModeRule = 40011;
constexpr UINT kCmdModeGlobal = 40012;
constexpr UINT kCmdModeDirect = 40013;
constexpr UINT kCmdAutoSelect = 40021;
constexpr UINT kCmdNodeBase = 40100;
constexpr UINT kCmdQuit = 40999;

HWND g_hwnd = nullptr;
bool g_connected = false;
std::string g_node_name;
std::string g_mode = "rule";
std::vector<TrayNodeEntry> g_nodes;
std::string g_selected_node_id;
bool g_auto_select_active = false;
bool g_tray_created = false;

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_invoke_channel;
std::mutex g_mutex;

std::wstring Utf8ToWideLocal(const std::string& s) {
  if (s.empty()) return {};
  const int size =
      MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  if (size <= 0) return {};
  std::wstring out(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, out.data(), size);
  return out;
}

void AppendMenuUtf8(HMENU menu, UINT flags, UINT_PTR id, const char* text) {
  AppendMenuW(menu, flags, id, Utf8ToWideLocal(text).c_str());
}

void InvokeFlutterAction(
    const std::string& action,
    const flutter::EncodableMap& extra = flutter::EncodableMap()) {
  if (!g_invoke_channel) return;
  flutter::EncodableMap args;
  args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  for (const auto& entry : extra) {
    args[entry.first] = entry.second;
  }
  g_invoke_channel->InvokeMethod(
      "menuAction",
      std::make_unique<flutter::EncodableValue>(flutter::EncodableValue(args)));
}

void EnsureTrayIcon(HWND hwnd) {
  if (g_tray_created) return;
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = 1;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayCallbackMessage;
  nid.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(101));
  if (!nid.hIcon) {
    nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }
  wcscpy_s(nid.szTip, L"\u7075\u732b\u52a0\u901f\u5668");
  Shell_NotifyIconW(NIM_ADD, &nid);
  g_tray_created = true;
}

HMENU BuildNodesSubmenu() {
  HMENU submenu = CreatePopupMenu();
  if (g_nodes.empty()) {
    AppendMenuUtf8(submenu, MF_STRING | MF_GRAYED, 0, "\u6682\u65e0\u8282\u70b9");
    return submenu;
  }
  for (size_t i = 0; i < g_nodes.size(); ++i) {
    const auto& node = g_nodes[i];
    const std::string title = node.name.empty() ? node.id : node.name;
    UINT flags = MF_STRING;
    if (!g_selected_node_id.empty() && node.id == g_selected_node_id) {
      flags |= MF_CHECKED;
    }
    AppendMenuUtf8(submenu, flags, kCmdNodeBase + static_cast<UINT>(i),
                   title.c_str());
  }
  return submenu;
}

bool DispatchTrayCommand(HWND hwnd, UINT command_id);

void ShowContextMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  AppendMenuUtf8(menu, MF_STRING, kCmdShow, "\u663e\u793a\u4e3b\u7a97\u53e3");
  AppendMenuUtf8(menu, MF_STRING, kCmdToggle,
                 g_connected ? "\u65ad\u5f00\u8fde\u63a5" : "\u8fde\u63a5");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  auto add_mode = [&](const char* title, UINT id, const char* mode) {
    UINT flags = MF_STRING;
    if (g_mode == mode) flags |= MF_CHECKED;
    AppendMenuUtf8(menu, flags, id, title);
  };
  add_mode("\u89c4\u5219", kCmdModeRule, "rule");
  add_mode("\u5168\u5c40", kCmdModeGlobal, "global");
  add_mode("\u76f4\u8fde", kCmdModeDirect, "direct");

  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  UINT auto_flags = MF_STRING;
  if (g_auto_select_active) auto_flags |= MF_CHECKED;
  AppendMenuUtf8(menu, auto_flags, kCmdAutoSelect, "\u81ea\u52a8\u9009\u62e9");

  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  HMENU nodes_menu = BuildNodesSubmenu();
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(nodes_menu),
              Utf8ToWideLocal("\U0001f680 \u8282\u70b9\u9009\u62e9").c_str());

  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuUtf8(menu, MF_STRING, kCmdQuit, "\u9000\u51fa");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(hwnd);
  const UINT cmd =
      TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                     cursor.x, cursor.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
  if (cmd != 0) {
    DispatchTrayCommand(hwnd, cmd);
  }
  PostMessage(hwnd, WM_NULL, 0, 0);
}

bool DispatchTrayCommand(HWND hwnd, UINT command_id) {
  if (command_id == kCmdShow) {
    ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
    return true;
  }
  if (command_id == kCmdToggle) {
    InvokeFlutterAction("toggleConnection");
    ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
    return true;
  }
  if (command_id == kCmdModeRule) {
    flutter::EncodableMap extra;
    extra[flutter::EncodableValue("mode")] = flutter::EncodableValue("rule");
    InvokeFlutterAction("setMode", extra);
    return true;
  }
  if (command_id == kCmdModeGlobal) {
    flutter::EncodableMap extra;
    extra[flutter::EncodableValue("mode")] =
        flutter::EncodableValue("global");
    InvokeFlutterAction("setMode", extra);
    return true;
  }
  if (command_id == kCmdModeDirect) {
    flutter::EncodableMap extra;
    extra[flutter::EncodableValue("mode")] =
        flutter::EncodableValue("direct");
    InvokeFlutterAction("setMode", extra);
    return true;
  }
  if (command_id == kCmdAutoSelect) {
    InvokeFlutterAction("selectAuto");
    return true;
  }
  if (command_id >= kCmdNodeBase &&
      command_id < kCmdNodeBase + static_cast<UINT>(g_nodes.size())) {
    const size_t index = command_id - kCmdNodeBase;
    const auto& node = g_nodes[index];
    flutter::EncodableMap extra;
    extra[flutter::EncodableValue("nodeId")] =
        flutter::EncodableValue(node.id);
    InvokeFlutterAction("selectNode", extra);
    return true;
  }
  if (command_id == kCmdQuit) {
    PostQuitMessage(0);
    return true;
  }
  return false;
}

}  // namespace

void TrayManager::Configure(HWND hwnd,
                            flutter::BinaryMessenger* messenger) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_hwnd = hwnd;
  if (messenger) {
    g_invoke_channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, "com.panlink.vpn/menu_bar",
            &flutter::StandardMethodCodec::GetInstance());
  }
  EnsureTrayIcon(hwnd);
}

void TrayManager::UpdateMenu(bool connected,
                             const std::string& node_name,
                             const std::string& mode,
                             const std::vector<TrayNodeEntry>& nodes,
                             const std::string& selected_node_id,
                             bool auto_select_active) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_connected = connected;
  g_node_name = node_name;
  g_mode = mode.empty() ? "rule" : mode;
  g_nodes = nodes;
  g_selected_node_id = selected_node_id;
  g_auto_select_active = auto_select_active;

  if (!g_hwnd) return;
  EnsureTrayIcon(g_hwnd);

  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = g_hwnd;
  nid.uID = 1;
  nid.uFlags = NIF_TIP;
  std::wstring tip = L"\u7075\u732b\u52a0\u901f\u5668";
  if (connected) {
    tip += L" \u00b7 \u5df2\u8fde\u63a5";
    if (!g_node_name.empty()) {
      tip += L" \u00b7 ";
      tip += Utf8ToWideLocal(g_node_name);
    }
  } else {
    tip += L" \u00b7 \u672a\u8fde\u63a5";
  }
  wcsncpy_s(nid.szTip, tip.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

LRESULT TrayManager::HandleTrayMessage(HWND hwnd, WPARAM wparam,
                                       LPARAM lparam) {
  switch (LOWORD(lparam)) {
    case WM_LBUTTONUP:
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
      return 0;
    case WM_RBUTTONUP:
      ShowContextMenu(hwnd);
      return 0;
    case NIN_SELECT:
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
      return 0;
    default:
      return 0;
  }
}

bool TrayManager::HandleCommand(HWND hwnd, UINT command_id) {
  return DispatchTrayCommand(hwnd, command_id);
}

void TrayManager::Dispose() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_tray_created && g_hwnd) {
    NOTIFYICONDATAW nid{};
    nid.cbSize = sizeof(nid);
    nid.hWnd = g_hwnd;
    nid.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &nid);
    g_tray_created = false;
  }
  g_invoke_channel.reset();
  g_hwnd = nullptr;
}
