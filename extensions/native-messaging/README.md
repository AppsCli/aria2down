# Native Messaging Host（P5-08 ◐）

将浏览器扩展的链接转发到 **已运行** 的本机 aria2（通过 `rpc.secret`），无需在扩展中硬编码 token。

## 组件

| 文件 | 说明 |
| --- | --- |
| `com.aria2down.host.json` | Chrome 宿主清单（需填写扩展 ID） |
| `host.sh` | 启动 `dart run bin/native_messaging_host.dart` |
| `../../bin/native_messaging_host.dart` | 读 stdin JSON，调用 `addUrisViaStoredCredentials` |
| `../../bin/rpc_add_uri.dart` | 命令行同样能力 |

## 安装（Chrome，开发者）

1. 在 aria2down 中 **本机模式** 启动 aria2 至少一次（生成 `rpc.secret`）。
2. 获取扩展 ID（`chrome://extensions` → 开发者模式 → 已加载扩展的 ID）。
3. 执行（macOS / Linux）：

```bash
chmod +x extensions/native-messaging/host.sh
EXTENSION_ID=你的扩展ID ./scripts/install_native_messaging_host.sh
```

4. 重启 Chrome。

macOS 用户目录示例：`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`

## 消息格式

```json
{"url":"https://example.com/file.zip"}
```

响应：`{"ok":true,"gid":"...","uris":[...]}`

## 设置页快捷方式

应用 **设置 → 诊断 → 复制扩展用 RPC 配置** 可得到扩展选项页所需的 JSON。
