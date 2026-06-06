# 加速器（灵猫加速器 客户端）

基于 Flutter 的 **Xboard** 面板客户端，对接 [灵猫加速器](https://user.panlink.site)，内嵌 **mihomo** 内核（类 Clash Verge Rev 架构）。

## 功能模块

| 模块 | 说明 |
|------|------|
| **首页** | 流量、套餐到期、连接开关、节点选择 |
| **节点列表** | 节点状态；订阅导入 Clash / sing-box 等 |
| **配置管理** | 订阅链接、重置订阅 Token |
| **商店** | Xboard 套餐购买 |
| **个人中心** | 账户、充值记录、工单 |

## 架构

```
Flutter UI
    │  HTTP  Bearer (Xboard API)
    ▼
https://user.panlink.site/api/v1/...
    │
    │  连接时拉取 Clash 订阅
    ▼
mihomo 子进程 (fork)
    │  external-controller
    ▼
127.0.0.1:9090  REST API（切换节点、流量等）
```

- **面板**：Xboard `/api/v1/`（登录 `auth_data`、用户、节点、订单、工单）
- **代理内核**：启动时由原生层拉起 mihomo；UI 通过 `external-controller` 控制

## 运行

```bash
cd /Users/mac/Downloads/sspanel-app
flutter pub get

# macOS 需先安装 mihomo
brew install mihomo

flutter run -d macos
```

面板地址在 `lib/config/app_config.dart`：

| 配置项 | 说明 |
|--------|------|
| `baseUrl` | `https://user.panlink.site` |
| `mihomoControllerPort` | REST API 端口（默认 9090） |
| `mihomoMixedPort` | 本地混合代理端口（默认 7890） |

## 登录

使用在 [user.panlink.site](https://user.panlink.site) 注册的邮箱与密码。Token 保存在本地 `SharedPreferences`，下次自动登录。

## Mihomo 说明

1. 应用启动后在后台启动 mihomo（空配置 + external-controller）
2. 点击连接：拉取 `subscribe_url?flag=clash`，写入配置并重启 mihomo
3. 切换节点：调用 `PUT /proxies/{组名}` 选择代理
4. **系统代理**：连接后自动将 macOS 系统 HTTP/HTTPS/SOCKS 代理设为 `127.0.0.1:7890`（可在首页或设置中开关）
5. **实时流量**：首页连接后显示 mihomo `/traffic` 流式上下行速率

若提示找不到 mihomo：

```bash
brew install mihomo
# 或将 mihomo 二进制放入 macos/Runner/Resources 并命名为 mihomo
```

系统代理需自行指向 `127.0.0.1:7890`（macOS 上连接后会自动设置，也可在首页手动开关）。

## 项目结构

```
lib/
├── config/app_config.dart
├── services/
│   ├── xboard_api.dart
│   ├── xboard_http_client.dart
│   ├── mihomo_service.dart
│   ├── mihomo_api.dart
│   └── mihomo_bridge.dart
├── state/app_state.dart
└── screens/...
macos/Runner/MihomoManager.swift
```
