# JNI：hev-socks5-tunnel 按固定类名注册 native 方法，不可混淆
-keep class hev.sockstun.TProxyService { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class com.kele.kele_vpn.StarVpnService { *; }
-keep class com.kele.kele_vpn.MihomoManager { *; }
-keep class com.kele.kele_vpn.HevTunnelManager { *; }
