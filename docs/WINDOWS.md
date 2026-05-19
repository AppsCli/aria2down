# Windows 构建与内嵌 aria2c

对应规划 **P3-05 / P3-06**。Windows 上推荐先用 **Chocolatey** 或 **MSYS2** 获得 `aria2c.exe`，再打入 Flutter `Release` 目录。

## 快速：Chocolatey（开发 / CI）

```powershell
choco install aria2 -y
flutter build windows --release
./scripts/stage_windows_aria2.ps1
```

GitHub Actions 的 `windows-release-bundle` 作业已按此逻辑尝试拷贝 `aria2c.exe`。

## 从子模块编译（进阶）

aria2 上游提供 MinGW 相关 Dockerfile（见 `third_party/aria2`）。本仓库未默认在 Windows CI 编译子模块（耗时长、依赖多）。本地可参考：

- [docs/BUILD_ARIA2.md](BUILD_ARIA2.md)
- [docs/BUILD.md](BUILD.md) 中 Windows / MinGW 小节

## MSIX 分发

见 [MSIX.md](MSIX.md) 与 `scripts/package_msix.sh`。

## 注意

- Release 目录需同时包含 **Flutter 引擎 DLL** 与 **aria2c.exe**（及 aria2 依赖的 VC 运行库）。
- 未签名 exe 可能触发 SmartScreen；正式分发需代码签名。
