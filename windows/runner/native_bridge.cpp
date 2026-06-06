#include "native_bridge.h"

#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "mihomo_manager.h"
#include "system_proxy_manager.h"

namespace {

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_mihomo_channel;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_proxy_channel;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_menu_channel;

int GetIntArg(const flutter::EncodableMap* map, const char* key) {
  if (!map) return 0;
  auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return 0;
  if (auto v = std::get_if<int32_t>(&it->second)) return *v;
  if (auto v = std::get_if<int64_t>(&it->second)) return static_cast<int>(*v);
  return 0;
}

std::string GetStringArg(const flutter::EncodableMap* map, const char* key) {
  if (!map) return {};
  auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return {};
  if (auto v = std::get_if<std::string>(&it->second)) return *v;
  return {};
}

}  // namespace

void RegisterPanlinkChannels(flutter::FlutterViewController* controller) {
  auto messenger = controller->engine()->messenger();
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();

  g_mihomo_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.panlink.vpn/mihomo", codec);
  g_mihomo_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "resolveBinary") {
          result->Success(flutter::EncodableValue(MihomoManager::ResolveBinary()));
        } else if (call.method_name() == "lastStartError") {
          result->Success(flutter::EncodableValue(MihomoManager::LastStartError()));
        } else if (call.method_name() == "start") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          const std::string path = GetStringArg(args, "configPath");
          result->Success(flutter::EncodableValue(MihomoManager::Start(path)));
        } else if (call.method_name() == "stop") {
          MihomoManager::Stop();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  g_proxy_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.panlink.vpn/system_proxy", codec);
  g_proxy_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "enable") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          const std::string host = GetStringArg(args, "host");
          const int port = GetIntArg(args, "port");
          result->Success(
              flutter::EncodableValue(SystemProxyManager::Enable(host, port)));
        } else if (call.method_name() == "disable") {
          result->Success(flutter::EncodableValue(SystemProxyManager::Disable()));
        } else if (call.method_name() == "isEnabled") {
          result->Success(
              flutter::EncodableValue(SystemProxyManager::IsEnabled()));
        } else {
          result->NotImplemented();
        }
      });

  g_menu_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.panlink.vpn/menu_bar", codec);
  g_menu_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "updateMenu") {
          // Windows 托盘 UI 后续扩展；先保证 channel 可用
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}
