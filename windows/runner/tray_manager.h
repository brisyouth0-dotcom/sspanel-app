#pragma once

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <string>
#include <vector>

struct TrayNodeEntry {
  std::string id;
  std::string name;
};

/// Windows 系统托盘菜单（对齐 macOS StatusBarManager）
class TrayManager {
 public:
  static void Configure(HWND hwnd, flutter::BinaryMessenger* messenger);
  static void UpdateMenu(bool connected,
                         const std::string& node_name,
                         const std::string& mode,
                         const std::vector<TrayNodeEntry>& nodes,
                         const std::string& selected_node_id,
                         bool auto_select_active);
  static LRESULT HandleTrayMessage(HWND hwnd, WPARAM wparam, LPARAM lparam);
  static bool HandleCommand(HWND hwnd, UINT command_id);
  static void Dispose();
};
