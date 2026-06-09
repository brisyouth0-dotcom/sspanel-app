#include "mihomo_manager.h"

#include <windows.h>
#include <tlhelp32.h>

#include <filesystem>
#include <fstream>
#include <mutex>
#include <sstream>
#include <thread>

namespace fs = std::filesystem;

void* MihomoManager::process_handle_ = nullptr;
unsigned long MihomoManager::process_id_ = 0;
std::string MihomoManager::last_error_;
std::mutex MihomoManager::mutex_{};

static std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string out(size - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, out.data(), size, nullptr, nullptr);
  return out;
}

static std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring out(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, out.data(), size);
  return out;
}

std::string MihomoManager::ResolveBinary() {
  wchar_t exe_path[MAX_PATH];
  GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  fs::path dir = fs::path(exe_path).parent_path();
  const fs::path candidates[] = {
      dir / L"mihomo-compatible.exe",
      dir / L"mihomo.exe",
      dir / L"data" / L"mihomo-compatible.exe",
      dir / L"data" / L"mihomo.exe",
      dir / L".." / L".." / L"Resources" / L"mihomo-compatible.exe",
      dir / L".." / L".." / L"Resources" / L"mihomo.exe",
  };
  for (const auto& c : candidates) {
    if (fs::exists(c)) return WideToUtf8(c.wstring());
  }
  last_error_ = "未找到 mihomo.exe，请运行 scripts/download_mihomo_windows.sh";
  return {};
}

static bool IsMihomoImageName(const wchar_t* image_name) {
  if (!image_name || image_name[0] == L'\0') return false;
  std::wstring lower(image_name);
  for (wchar_t& ch : lower) {
    ch = static_cast<wchar_t>(towlower(ch));
  }
  return lower.find(L"mihomo") != std::wstring::npos;
}

/// 清理所有 mihomo 相关进程（含 Temp 目录下的 mihomo-windows-amd64-compatible.exe）
static void KillOrphanedMihomoProcesses(unsigned long skip_pid = 0) {
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap != INVALID_HANDLE_VALUE) {
    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe)) {
      do {
        if (!IsMihomoImageName(pe.szExeFile)) continue;
        const DWORD pid = pe.th32ProcessID;
        if (pid <= 4 || pid == skip_pid) continue;
        HANDLE proc =
            OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, pid);
        if (!proc) continue;
        TerminateProcess(proc, 0);
        WaitForSingleObject(proc, 2000);
        CloseHandle(proc);
      } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
  }
  Sleep(650);
}

bool MihomoManager::Start(const std::string& config_path) {
  std::lock_guard<std::mutex> lock(mutex_);
  StopUnlocked();
  KillOrphanedMihomoProcesses();
  last_error_.clear();
  const std::string binary = ResolveBinary();
  if (binary.empty()) return false;

  const fs::path cfg(config_path);
  const fs::path work_dir = cfg.parent_path();
  std::wstring cmd = L"\"" + Utf8ToWide(binary) + L"\" -d \"" +
                     Utf8ToWide(work_dir.string()) + L"\" -f \"" +
                     Utf8ToWide(config_path) + L"\"";

  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  std::vector<wchar_t> cmd_buf(cmd.begin(), cmd.end());
  cmd_buf.push_back(L'\0');
  if (!CreateProcessW(nullptr, cmd_buf.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr,
                      Utf8ToWide(work_dir.string()).c_str(), &si, &pi)) {
    last_error_ = "启动失败：CreateProcess 错误 " + std::to_string(GetLastError());
    return false;
  }
  process_handle_ = pi.hProcess;
  process_id_ = pi.dwProcessId;
  CloseHandle(pi.hThread);
  const DWORD wait = WaitForSingleObject(pi.hProcess, 800);
  DWORD exit_code = STILL_ACTIVE;
  GetExitCodeProcess(pi.hProcess, &exit_code);
  if (wait == WAIT_OBJECT_0 && exit_code != STILL_ACTIVE) {
    if (exit_code == 3221225477UL) {
      last_error_ =
          "mihomo 进程崩溃（0xC0000005）。请使用 compatible 版本："
          "scripts/download_mihomo_windows.sh";
    } else {
      last_error_ = "mihomo 进程已退出（code " + std::to_string(exit_code) + "）";
    }
    StopUnlocked();
    return false;
  }
  return true;
}

void MihomoManager::StopUnlocked() {
  const unsigned long tracked = process_id_;
  if (process_handle_) {
    TerminateProcess(static_cast<HANDLE>(process_handle_), 0);
    WaitForSingleObject(static_cast<HANDLE>(process_handle_), 3000);
    CloseHandle(static_cast<HANDLE>(process_handle_));
    process_handle_ = nullptr;
    process_id_ = 0;
  }
  KillOrphanedMihomoProcesses(tracked);
}

void MihomoManager::Stop() {
  std::lock_guard<std::mutex> lock(mutex_);
  StopUnlocked();
}

bool MihomoManager::IsProcessRunning() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!process_handle_) return false;
  DWORD exit_code = STILL_ACTIVE;
  if (!GetExitCodeProcess(static_cast<HANDLE>(process_handle_), &exit_code)) {
    return false;
  }
  return exit_code == STILL_ACTIVE;
}

std::string MihomoManager::LastStartError() { return last_error_; }
