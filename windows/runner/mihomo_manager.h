#pragma once

#include <string>

class MihomoManager {
 public:
  static std::string ResolveBinary();
  static bool Start(const std::string& config_path);
  static void Stop();
  static std::string LastStartError();

 private:
  static void* process_handle_;
  static unsigned long process_id_;
  static std::string last_error_;
};
