#include "system_proxy_manager.h"

#include <cstdlib>
#include <sstream>

bool SystemProxyManager::active_ = false;

static int RunCommand(const std::string& cmd) {
  return std::system(cmd.c_str());
}

bool SystemProxyManager::Enable(const std::string& host, int port) {
  std::ostringstream manual;
  manual << "gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null";
  RunCommand(manual.str());
  std::ostringstream http;
  http << "gsettings set org.gnome.system.proxy.http host '" << host
       << "' 2>/dev/null";
  RunCommand(http.str());
  std::ostringstream http_port;
  http_port << "gsettings set org.gnome.system.proxy.http port " << port
            << " 2>/dev/null";
  RunCommand(http_port.str());
  std::ostringstream socks;
  socks << "gsettings set org.gnome.system.proxy.socks host '" << host
        << "' 2>/dev/null";
  RunCommand(socks.str());
  std::ostringstream socks_port;
  socks_port << "gsettings set org.gnome.system.proxy.socks port " << port
             << " 2>/dev/null";
  RunCommand(socks_port.str());
  active_ = true;
  return true;
}

bool SystemProxyManager::Disable() {
  RunCommand("gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null");
  active_ = false;
  return true;
}

bool SystemProxyManager::IsEnabled() { return active_; }
