# 应用内深链（新建任务）

aria2down 使用 [go_router](https://pub.dev/packages/go_router) 路径，可在桌面端通过导航或分享链接预填「新建任务」页。

## 格式

| 场景 | 路径示例 |
| --- | --- |
| 单个 URL | `/add?uri=https%3A%2F%2Fexample.com%2Ffile.zip` |
| 多个 URL | `/add?uris=https%3A%2F%2Fa%0Amagnet%3A%3Fxt%3D...`（`uris` 值为换行分隔，整体需 URL 编码） |

Dart 辅助函数：`lib/core/app_deep_link.dart` 中的 `buildInAppAddPath` / `buildInAppAddPathForUris`。

## 使用方式

1. **任务详情** → 工具栏「复制应用内添加链接」，将路径粘贴到浏览器地址栏或自定义启动参数（若已注册 URL scheme）。
2. 在应用内：`context.go('/add?uri=...')` 或 `GoRouter.of(context).go(buildInAppAddPath(uri))`。

## 与浏览器扩展

扩展仍直接调用 aria2 JSON-RPC。深链仅用于 **aria2down GUI** 预填，不替代扩展的 `addUri`。
