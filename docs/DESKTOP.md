# 桌面端快速参考

## 日常开发

```bash
flutter run -d macos    # 或 linux / windows
```

## 打包（含 aria2c）

```bash
./scripts/build_bundle_with_aria2.sh linux
# 产物：build/dist/
```

仅打包（系统 aria2c）：

```bash
./scripts/package_desktop.sh macos
```

## Windows MSIX

见 [MSIX.md](MSIX.md)。

## 本机 RPC（扩展 / 脚本）

应用启动本机 aria2 后，凭据写入应用支持目录下的 `rpc.secret`（端口 + token）。

```bash
dart run bin/rpc_add_uri.dart 'https://example.com/file.zip'
```

浏览器扩展 Native Messaging 草案见 `extensions/native-messaging/`。

## 快捷键

| 快捷键 | 动作 |
| --- | --- |
| ⌘/Ctrl+R | 刷新任务列表 |
| ⌘/Ctrl+, | 打开设置 |
