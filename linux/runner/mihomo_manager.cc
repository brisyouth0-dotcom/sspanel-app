#include "mihomo_manager.h"

#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <thread>

namespace fs = std::filesystem;

pid_t MihomoManager::process_id_ = -1;
std::string MihomoManager::last_error_;

static bool IsExecutable(const fs::path& p) {
  struct stat st {};
  return stat(p.c_str(), &st) == 0 && (st.st_mode & S_IXUSR);
}

std::string MihomoManager::ResolveBinary() {
  char exe[4096];
  ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
  if (len > 0) {
    exe[len] = '\0';
    fs::path dir = fs::path(exe).parent_path();
    const fs::path candidates[] = {
        dir / "mihomo",
        dir / "data" / "mihomo",
        dir / ".." / ".." / "bundle" / "mihomo",
    };
    for (const auto& c : candidates) {
      if (IsExecutable(c)) return c.string();
    }
  }
  const char* path_env = getenv("PATH");
  if (path_env) {
    std::string paths(path_env);
    size_t start = 0;
    while (start < paths.size()) {
      size_t end = paths.find(':', start);
      if (end == std::string::npos) end = paths.size();
      fs::path candidate = fs::path(paths.substr(start, end - start)) / "mihomo";
      if (IsExecutable(candidate)) return candidate.string();
      start = end + 1;
    }
  }
  last_error_ = "未找到 mihomo，请运行 scripts/download_mihomo_linux.sh";
  return {};
}

bool MihomoManager::Start(const std::string& config_path) {
  Stop();
  last_error_.clear();
  const std::string binary = ResolveBinary();
  if (binary.empty()) return false;

  const fs::path cfg(config_path);
  const std::string work_dir = cfg.parent_path().string();
  pid_t pid = fork();
  if (pid < 0) {
    last_error_ = "fork 失败";
    return false;
  }
  if (pid == 0) {
    chdir(work_dir.c_str());
    execl(binary.c_str(), binary.c_str(), "-d", work_dir.c_str(), "-f",
          config_path.c_str(), nullptr);
    _exit(127);
  }
  process_id_ = pid;
  std::this_thread::sleep_for(std::chrono::milliseconds(500));
  int status = 0;
  pid_t r = waitpid(pid, &status, WNOHANG);
  if (r == pid) {
    last_error_ = "mihomo 进程已退出";
    process_id_ = -1;
    return false;
  }
  return true;
}

void MihomoManager::Stop() {
  if (process_id_ > 0) {
    kill(process_id_, SIGTERM);
    waitpid(process_id_, nullptr, 0);
    process_id_ = -1;
  }
}

std::string MihomoManager::LastStartError() { return last_error_; }
