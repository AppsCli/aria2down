# iOS 打包说明（P4-07）

> iOS **无法**像桌面一样内嵌并执行 `aria2c` 子进程。MVP 请使用 **远程 RPC**，见 [IOS.md](IOS.md)。

## 构建 IPA（需 macOS + Xcode）

```bash
flutter pub get
flutter build ipa --release
```

产物位于 `build/ios/ipa/`。上架 App Store 需 Apple Developer 账号、签名与描述文件。

## 测试安装

```bash
flutter build ios --release
# 在 Xcode 中打开 ios/Runner.xcworkspace，选择真机 Run
```

## CI

当前仓库 CI **未**自动生成 ipa（需 macOS 签名环境）。可在 `workflow_dispatch` 的 macOS runner 上手动添加 `flutter build ipa --no-codesign` 作烟雾构建。

## 与 Android 对比

| 平台 | 本机 aria2 | 推荐模式 |
| --- | --- | --- |
| Android | 可内嵌 NDK 二进制（P4-01） | 远程或内嵌 |
| iOS | 不可执行外部二进制 | **远程 RPC** |
