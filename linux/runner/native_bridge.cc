#include "native_bridge.h"

#include <flutter_linux/flutter_linux.h>

#include "mihomo_manager.h"
#include "system_proxy_manager.h"

static FlMethodChannel* g_mihomo_channel = nullptr;
static FlMethodChannel* g_proxy_channel = nullptr;
static FlMethodChannel* g_menu_channel = nullptr;

static void MihomoHandler(FlMethodChannel* channel, FlMethodCall* method_call,
                          gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "resolveBinary") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string(MihomoManager::ResolveBinary().c_str())));
  } else if (g_strcmp0(method, "lastStartError") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string(MihomoManager::LastStartError().c_str())));
  } else if (g_strcmp0(method, "start") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const char* path = fl_value_lookup_string(args, "configPath");
    bool ok = path ? MihomoManager::Start(path) : false;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(ok)));
  } else if (g_strcmp0(method, "stop") == 0) {
    MihomoManager::Stop();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void ProxyHandler(FlMethodChannel* channel, FlMethodCall* method_call,
                         gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  FlValue* args = fl_method_call_get_args(method_call);
  if (g_strcmp0(method, "enable") == 0) {
    const char* host = fl_value_lookup_string(args, "host");
    int64_t port = fl_value_lookup_int(args, "port");
    bool ok = SystemProxyManager::Enable(host ? host : "127.0.0.1",
                                         static_cast<int>(port));
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(ok)));
  } else if (g_strcmp0(method, "disable") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(SystemProxyManager::Disable())));
  } else if (g_strcmp0(method, "isEnabled") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(SystemProxyManager::IsEnabled())));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void MenuHandler(FlMethodChannel* channel, FlMethodCall* method_call,
                        gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "updateMenu") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

void RegisterPanlinkChannels(FlEngine* engine) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_mihomo_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "com.panlink.vpn/mihomo",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_mihomo_channel, MihomoHandler,
                                          nullptr, nullptr);

  g_proxy_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "com.panlink.vpn/system_proxy",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_proxy_channel, ProxyHandler,
                                          nullptr, nullptr);

  g_menu_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "com.panlink.vpn/menu_bar",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_menu_channel, MenuHandler, nullptr,
                                          nullptr);
}
