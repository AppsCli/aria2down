# 参考项目与资料

> 本文档汇总开发 `aria2down` 时可参考的开源项目、官方文档与技术资料。
> 所有参考项目均为 **学习用途**，本项目自行实现 UI 与集成层，仅复用 aria2 内核。

---

## 1. aria2 官方资料（必读）

| 资料 | 链接 | 说明 |
| --- | --- | --- |
| aria2 项目主页 | <https://aria2.github.io/> | 官方网站 |
| GitHub 仓库 | <https://github.com/aria2/aria2> | 源码（已作为本项目子模块 `third_party/aria2`） |
| 用户手册（man） | <https://aria2.github.io/manual/en/html/aria2c.html> | 全部命令行选项与配置项 |
| RPC 接口手册 | <https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface> | **核心参考**：所有 JSON-RPC 方法、参数、返回值、通知 |
| 编译指南 | <https://github.com/aria2/aria2/blob/master/README.rst> | 各平台编译说明 |
| Android Dockerfile | `third_party/aria2/Dockerfile.android` | 用于交叉编译 Android 二进制 |
| MinGW Dockerfile | `third_party/aria2/Dockerfile.mingw` | 用于交叉编译 Windows 二进制 |
| Raspberry Pi Dockerfile | `third_party/aria2/Dockerfile.raspberrypi` | 用于交叉编译 ARM 二进制 |

### aria2 关键 RPC 方法速查

```
aria2.addUri(secret, [uris], options?)         # 添加 HTTP/FTP/磁力 任务
aria2.addTorrent(secret, base64_torrent, ...)  # 添加 BT 任务
aria2.addMetalink(secret, base64_metalink)     # 添加 Metalink 任务
aria2.remove(secret, gid)                      # 删除任务（优雅）
aria2.forceRemove(secret, gid)                 # 删除任务（强制）
aria2.pause(secret, gid)                       # 暂停
aria2.unpause(secret, gid)                     # 继续
aria2.tellStatus(secret, gid, keys?)           # 任务详情
aria2.tellActive(secret, keys?)                # 进行中任务
aria2.tellWaiting(secret, offset, num, keys?)  # 等待中任务
aria2.tellStopped(secret, offset, num, keys?)  # 已停止/完成任务
aria2.getGlobalStat(secret)                    # 全局速度/任务数
aria2.getOption(secret, gid)                   # 任务选项
aria2.changeOption(secret, gid, options)       # 修改任务选项
aria2.getGlobalOption(secret)                  # 全局选项
aria2.changeGlobalOption(secret, options)      # 修改全局选项
aria2.getVersion(secret)                       # aria2 版本
aria2.shutdown(secret)                         # 优雅关闭
aria2.forceShutdown(secret)                    # 强制关闭
system.multicall([{...}, {...}])               # 批量调用
```

### aria2 通知事件（WebSocket 推送）

```
aria2.onDownloadStart        # 任务开始
aria2.onDownloadPause        # 任务暂停
aria2.onDownloadStop         # 任务停止
aria2.onDownloadComplete     # 下载完成
aria2.onDownloadError        # 下载错误
aria2.onBtDownloadComplete   # BT 下载完成（开始做种）
```

---

## 2. 同类客户端参考项目

### 2.1 Motrix（**最重要参考**）

- 仓库：<https://github.com/agalwood/Motrix>
- 协议：MIT
- 技术栈：Electron + Vue 2 + Vuex
- 参考价值：
  - 完整的 aria2 集成方案（启动、配置、token、RPC 客户端）
  - 任务列表、新建任务、详情页、设置页 UI 设计
  - 多语言、托盘、自启实现
  - aria2 配置项的人性化映射（速度限制、连接数等）
- 重点关注源码：
  - `src/main/core/Engine.js` —— aria2 进程启动与生命周期
  - `src/shared/aria2c.js` —— 客户端封装
  - `src/renderer/components/Task/*` —— 任务相关组件

### 2.2 AriaNg

- 仓库：<https://github.com/mayswind/AriaNg>
- 协议：MIT
- 技术栈：AngularJS（纯前端，连接到外部 aria2）
- 参考价值：
  - aria2 RPC 调用全集（HTTP + WebSocket 两套）
  - 任务参数表单设计
  - 全局/任务级配置项的展示
- 重点关注源码：
  - `src/scripts/services/aria2.js`
  - `src/scripts/services/aria2WebSocketRpcService.js`
  - `src/scripts/services/aria2HttpRpcService.js`

### 2.3 Persepolis Download Manager

- 仓库：<https://github.com/persepolisdm/persepolis>
- 协议：GPLv3
- 技术栈：Python + PyQt5
- 参考价值：
  - 桌面三平台打包经验
  - aria2 子进程管理（Python 版）
  - 浏览器扩展集成方案
- 注意：GPLv3，仅作设计参考，不直接搬代码

### 2.4 aria2-android（Bitbucket / 各 fork）

- 类似项目：<https://github.com/devgianlu/Aria2App>
- 协议：GPLv3
- 技术栈：Android 原生（Java）
- 参考价值：
  - Android 内嵌 aria2 二进制 + Service 守护
  - 通知栏进度展示
  - 移动端 UI 适配

### 2.5 Aria2GUI (macOS)

- 仓库：<https://github.com/yangshun1029/aria2gui>
- 协议：GPLv3
- 技术栈：Swift
- 参考价值：macOS 启动 aria2c 子进程的细节

### 2.6 已有 Flutter 实现（少量参考）

- `aria2_dart`：<https://pub.dev/packages/aria2> （社区 Dart RPC 客户端，可参考接口设计）
- 各种小型 demo（GitHub 搜索 `flutter aria2`）

> **注意**：本项目自行实现客户端，避免引入维护不活跃的第三方包。可参考其设计但不依赖。

---

## 3. JSON-RPC 与 WebSocket 资料

| 资料 | 链接 |
| --- | --- |
| JSON-RPC 2.0 规范 | <https://www.jsonrpc.org/specification> |
| Dart `web_socket_channel` | <https://pub.dev/packages/web_socket_channel> |
| Dart `dio` | <https://pub.dev/packages/dio> |

---

## 4. Flutter 相关资料

| 主题 | 资料 |
| --- | --- |
| Flutter 桌面 | <https://docs.flutter.dev/platform-integration/desktop> |
| Riverpod | <https://riverpod.dev/> |
| GoRouter | <https://pub.dev/packages/go_router> |
| Material 3 | <https://m3.material.io/> |
| 国际化 | <https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization> |
| 桌面窗口管理 | <https://pub.dev/packages/window_manager> |
| 系统托盘 | <https://pub.dev/packages/tray_manager> |
| 自启动 | <https://pub.dev/packages/launch_at_startup> |
| 文件选择 | <https://pub.dev/packages/file_selector> |
| 进程管理 | Dart 标准库 `dart:io` 的 `Process` 类 |

---

## 5. aria2 编译相关

| 平台 | 资料 |
| --- | --- |
| 通用（autotools） | `third_party/aria2/README.rst` |
| macOS | Homebrew 依赖：`brew install autoconf automake libtool pkg-config gettext openssl libssh2 c-ares` |
| Windows | <https://aria2.github.io/manual/en/html/README.html#how-to-build-aria2-windows-binary> |
| Android | `third_party/aria2/Dockerfile.android` + `README.android` |
| iOS（社区方案） | 搜索 `aria2 ios static library`，需评估静态链接 + 直接调用 main 的可行性 |

---

## 6. 许可证（License）相关

- aria2 采用 **GPLv2+**（含 OpenSSL 例外条款）。
- 本项目静态/动态链接 aria2 时，**整体必须以兼容 GPLv2+ 的协议开源**。
- 计划采用 **GPLv2+** 协议发布。
- 详见：
  - <https://www.gnu.org/licenses/gpl-2.0.html>
  - <https://github.com/aria2/aria2/blob/master/COPYING>

---

## 7. 浏览器扩展集成（远期）

| 资料 | 链接 |
| --- | --- |
| Chrome Native Messaging | <https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging> |
| Motrix 浏览器扩展 | <https://github.com/agalwood/Motrix-Webextension> |

---

## 8. UX 灵感

| 项目 | 看点 |
| --- | --- |
| qBittorrent | BT 任务详情 / Tracker 列表设计 |
| Free Download Manager | 任务分类、限速 |
| IDM | 浏览器集成捕获 |
| Motrix | 一致的现代化 Material UX |
| Maestral | 简洁的 macOS 桌面应用风格 |

---

## 9. 推荐学习路径（开发者上手）

1. 阅读 [aria2 RPC 接口手册](https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface) 全文。
2. 在本机手动启动 aria2c：
   ```bash
   aria2c --enable-rpc --rpc-listen-all=false --rpc-secret=test \
          --rpc-listen-port=6800 --dir=/tmp/aria2-test
   ```
3. 用 `curl` 或 Postman 调用 RPC，理解请求/响应。
4. 阅读 Motrix 与 AriaNg 的客户端源码。
5. 阅读 `PLAN.md` 与 `docs/ARCHITECTURE.md`。
6. 选择 WBS 中一个未完成任务开始动手。
