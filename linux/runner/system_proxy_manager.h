#pragma once

#include <string>

class SystemProxyManager {
 public:
  static bool Enable(const std::string& host, int port);
  static bool Disable();
  static bool IsEnabled();

 private:
  static bool active_;
};
