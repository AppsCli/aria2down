# 从源码构建 aria2c（P1-01 / P1-02）

桌面安装包内嵌 `aria2c` 前，需在本机或 CI 中编译 `third_party/aria2`。

## 前置条件

- 已初始化子模块：`git submodule update --init --recursive third_party/aria2`
- **macOS**：Xcode CLT、`autoconf` / `automake` / `libtool`（`brew install autoconf automake libtool`）
- **Linux**：`build-essential`、`autoconf`、`automake`、`libtool`、`pkg-config`、开发库（`libssl-dev`、`zlib1g-dev` 等，与发行版文档一致）

## 一键脚本

```bash
# 动态链接（开发机）
./scripts/build_aria2.sh

# 静态链接（Windows 发布包等，体积更大）
./scripts/build_aria2.sh --static
```

产物默认位于：`third_party/aria2/src/aria2c`（或 `aria2c.exe`）。

## 打入 Flutter 桌面 bundle

```bash
flutter build macos --release   # 或 linux / windows
./scripts/stage_aria2c.sh macos third_party/aria2/src/aria2c
./scripts/package_desktop.sh macos
```

## CI 说明

当前 GitHub Actions 在 **Linux / macOS / Windows** 构建中使用系统包管理器提供的 `aria2c` 做 **冒烟打包**（`stage_aria2c`），与「从子模块编译」不等价。正式发布建议在 release 流水线中调用 `build_aria2.sh` 后再 `stage_aria2c.sh`。

## Android（P4-01）

NDK 交叉编译尚未自动化，见 [ANDROID.md](ANDROID.md) 与 `scripts/stage_android_aria2.sh`。
