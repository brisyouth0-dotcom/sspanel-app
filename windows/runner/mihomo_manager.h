#pragma once

#include <mutex>
#include <string>

class MihomoManager {
 public:
  static std::string ResolveBinary();
  static bool Start(const std::string& config_path);
  static void Stop();
  static bool IsProcessRunning();
  static std::string LastStartError();

 private:
  static void StopUnlocked();
  static void* process_handle_;
  static unsigned long process_id_;
  static std::string last_error_;
  static std::mutex mutex_;
};
