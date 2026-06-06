#include "system_proxy_manager.h"

#include <windows.h>

#include <sstream>

bool SystemProxyManager::active_ = false;
bool SystemProxyManager::backup_enable_ = false;
std::string SystemProxyManager::backup_server_;

static bool ReadDword(HKEY key, const wchar_t* name, DWORD* out) {
  DWORD type = REG_DWORD;
  DWORD size = sizeof(DWORD);
  return RegQueryValueExW(key, name, nullptr, &type,
                          reinterpret_cast<LPBYTE>(out), &size) == ERROR_SUCCESS;
}

static bool ReadString(HKEY key, const wchar_t* name, std::string* out) {
  wchar_t buf[512];
  DWORD size = sizeof(buf);
  DWORD type = REG_SZ;
  if (RegQueryValueExW(key, name, nullptr, &type,
                        reinterpret_cast<LPBYTE>(buf), &size) != ERROR_SUCCESS) {
    return false;
  }
  int len = WideCharToMultiByte(CP_UTF8, 0, buf, -1, nullptr, 0, nullptr, nullptr);
  out->assign(len - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, buf, -1, out->data(), len, nullptr, nullptr);
  return true;
}

bool SystemProxyManager::Enable(const std::string& host, int port) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
                    0, KEY_READ | KEY_WRITE, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD enabled = 0;
  ReadDword(key, L"ProxyEnable", &enabled);
  backup_enable_ = enabled != 0;
  ReadString(key, L"ProxyServer", &backup_server_);

  std::ostringstream server;
  server << host << ":" << port;
  const std::string server_str = server.str();
  std::wstring wserver(server_str.begin(), server_str.end());
  DWORD on = 1;
  RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&on), sizeof(on));
  RegSetValueExW(key, L"ProxyServer", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(wserver.c_str()),
                 static_cast<DWORD>((wserver.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  active_ = true;
  return true;
}

bool SystemProxyManager::Disable() {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
                    0, KEY_READ | KEY_WRITE, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD enable = backup_enable_ ? 1 : 0;
  RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&enable), sizeof(enable));
  if (!backup_server_.empty()) {
    std::wstring wserver(backup_server_.begin(), backup_server_.end());
    RegSetValueExW(key, L"ProxyServer", 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(wserver.c_str()),
                   static_cast<DWORD>((wserver.size() + 1) * sizeof(wchar_t)));
  }
  RegCloseKey(key);
  active_ = false;
  return true;
}

bool SystemProxyManager::IsEnabled() { return active_; }
