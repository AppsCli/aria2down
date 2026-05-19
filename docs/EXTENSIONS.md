# 浏览器扩展（P5-08）

完整安装说明见 [extensions/README.md](../extensions/README.md)。本文档补充与 **aria2down 桌面端** 的协作方式。

## 组件

| 路径 | 说明 |
| --- | --- |
| `extensions/chrome/` | Manifest V3 |
| `extensions/firefox/` | Manifest V2 |
| `extensions/chrome/aria2_rpc.js` | 共用 JSON-RPC（`addUri`、`getVersion`） |
| `extensions/native-messaging/` | 可选：通过本机 `rpc.secret` 添加任务 |
| `bin/rpc_add_uri.dart` | 命令行 `addUri` |

## 与桌面端配置同步

1. 本机模式启动 aria2 一次。
2. 设置 → **复制扩展用 RPC 配置**。
3. 扩展选项页 → **Import from clipboard (JSON)** → **Test connection**。

## 远程 RPC / HTTPS

默认 `host_permissions` 仅含 `127.0.0.1` / `localhost`。连接 NAS 等远程地址时，需在 `manifest.json` 的 `host_permissions` 中增加对应 origin，或改用 **Native Messaging**（见 `extensions/native-messaging/README.md`）。

## 应用内深链

扩展不打开 GUI。要在 aria2down 中预填新建任务，见 [DEEPLINKS.md](DEEPLINKS.md)。
