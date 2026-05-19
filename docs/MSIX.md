# Windows MSIX 打包（P3-05）

## 前置

- Windows 10+ 开发机
- Flutter Windows 桌面已启用
- 项目已添加 `msix` 开发依赖（见 `pubspec.yaml` 的 `msix_config`）

## 命令

```powershell
# 一键（构建 + MSIX）
.\scripts\package_msix.sh

# 或分步
flutter build windows --release
dart run msix:create
```

产物通常在 `build/windows/x64/runner/Release/` 或 `build/windows/` 下的 `*.msix`，`package_msix.sh` 会复制到 `build/dist/`。

## 签名

商店或企业分发需 **代码签名证书**。未签名 MSIX 仅适合侧载测试；正式发版见 [RELEASE.md](RELEASE.md)。

## 与 zip 包关系

`package_desktop.sh windows` 仍生成 **zip**；MSIX 为可选第二产物，二者可并存。
