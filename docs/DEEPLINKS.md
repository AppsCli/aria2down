# 深链 / 外部唤起（让其它应用把下载交给 aria2down）

aria2down 同时支持「应用内深链」与「跨平台外部唤起」。无论是浏览器扩展、文件管理器双击、`magnet:` 协议处理、还是 Android 分享菜单 / macOS Finder「打开方式」，都能在打开新建任务页时自动预填或直接入队。

底层实现：基于 [app_links](https://pub.dev/packages/app_links) 监听各平台的 deep link 入口（Android `intent-filter`、iOS `CFBundleURLTypes` / `CFBundleDocumentTypes`、macOS Apple Event + Document Types、Linux `.desktop` + GApplication `HANDLES_OPEN`、Windows MSIX 协议激活）。

---

## 1. 自定义 Scheme：`aria2down://`

跨平台统一接口。任何能发起 URL 跳转的环境（浏览器地址栏、扩展、Shortcut、桌面快捷方式）都能唤起。

| 形式 | 含义 |
| --- | --- |
| `aria2down://add?uri=<encoded-url>` | 单链接，等价于应用内 `/add?uri=…` |
| `aria2down://add?uris=<encoded-newline-list>` | 多链接（`%0A` 分隔后整体 URL 编码） |
| `aria2down://add?url=<encoded-url>` | 兼容部分浏览器扩展惯用键名 |
| `aria2down://magnet?xt=urn:btih:…` | 等价于直接 `magnet:?xt=…` |
| `aria2down://<encoded-url>` | 兜底：把 path 当一条链接 |

调用示例（HTML/JS）：

```html
<a href="aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip">下载到 aria2down</a>
```

```javascript
// 浏览器扩展 / 油猴脚本
location.href =
  'aria2down://add?uri=' + encodeURIComponent(window.location.href);
```

---

## 2. 已支持的「免插件」唤起入口

| 入口 | macOS | Windows | Linux | Android | iOS |
| --- | --- | --- | --- | --- | --- |
| `aria2down://…` | ✓ | ✓ (MSIX) | ✓ (.desktop) | ✓ | ✓ |
| `magnet:?xt=…`（点击磁力链） | ✓（备选） | ✓（备选，MSIX） | ✓ | ✓ | ✓（备选） |
| 双击 `.torrent` / `.metalink` | ✓ | ✓ (MSIX) | ✓ | ✓ | ✓ |
| 分享菜单 → 发送到 aria2down | — | — | — | ✓ | （iOS Share Extension 暂未提供） |
| 浏览器右键 / 扩展 → 调 RPC | ✓ | ✓ | ✓ | — | — |

> 「备选」表示我们以 `LSHandlerRank=Alternate` 注册，不会抢系统默认；用户首次点击时由 OS 询问要用哪个应用。

进入应用后：

- **URL / 磁力** → 自动跳转 `/add?uri=…` 并预填，剩余流程同手动新建。
- **`.torrent` / `.metalink`** → 读取字节后直接调 `aria2.addTorrent` / `addMetalink`，多文件时弹窗让用户挑选要下的文件。
- **分享文本（Android）** → `ACTION_SEND` 携带的 `EXTRA_TEXT` 在 Kotlin 侧被重写为 `aria2down://add?uri=…`，再交给 app_links 统一派发。

---

## 3. 应用内深链（GoRouter）

仍然保留以方便在应用内分享、调试与扩展深链：

| 场景 | 路径示例 |
| --- | --- |
| 单个 URL | `/add?uri=https%3A%2F%2Fexample.com%2Ffile.zip` |
| 多个 URL | `/add?uris=https%3A%2F%2Fa%0Amagnet%3A%3Fxt%3D...` |

Dart 辅助函数：

- `lib/core/app_deep_link.dart` 的 `buildInAppAddPath` / `buildInAppAddPathForUris`（应用内）。
- `lib/core/incoming_link.dart` 的 `parseIncomingLink` / `buildAddPathFromIncoming`（外部唤起 → 应用内）。

任务详情页工具栏「复制应用内添加链接」可把 `/add?uri=…` 拷出粘贴到地址栏 / 启动参数；如果对方系统已注册 `aria2down://`，把前缀换成 `aria2down://add?uri=…` 即可在任意位置唤起。

---

## 4. 平台原生配置一览

> 这些已经在仓库中配置完成，下面列出仅为说明 / 自定义二次发布时参考。

### Android (`android/app/src/main/AndroidManifest.xml`)

- `flutter_deeplinking_enabled=false`（由 app_links 接管，避免与 Flutter 框架冲突）。
- `intent-filter`：
  - `aria2down://`（自定义 scheme，BROWSABLE）
  - `magnet:`（BROWSABLE）
  - `application/x-bittorrent` + `*.torrent` 路径匹配
  - `application/metalink+xml` + `application/metalink4+xml`
  - `ACTION_SEND` + `text/plain` / `text/x-uri`
- Kotlin `MainActivity`：
  - 新增 `MethodChannel('cloud.iothub.aria2down/incoming_link')` 的 `readContent`，用 `ContentResolver.openInputStream` 读取 `content://` 字节。
  - 重写 `onCreate` / `onNewIntent`：把 `ACTION_SEND` 的 `EXTRA_TEXT` 改写成 `ACTION_VIEW` + `aria2down://add?uri=…`，使 app_links 能统一处理。

### iOS (`ios/Runner/Info.plist`)

- `FlutterDeepLinkingEnabled=false`。
- `CFBundleURLTypes`：`aria2down` 与 `magnet`（备选）两个 scheme。
- `CFBundleDocumentTypes` + `UTImportedTypeDeclarations`：声明 `org.bittorrent.torrent`、`application.metalink` 两个 UTI，关联 `.torrent` / `.metalink` / `.meta4`。
- `LSHandlerRank=Alternate`，不强制成为默认。
- `LSSupportsOpeningDocumentsInPlace=true` + `UIFileSharingEnabled=true`：允许「文件」App 直接把 `.torrent` 用 aria2down 打开（in-place），并让 aria2down 沙盒目录出现在「文件」App 的「我的 iPhone」分组中，便于在第三方下载客户端之间转移种子文件。

### macOS (`macos/Runner/Info.plist`)

- 与 iOS 同结构的 `CFBundleURLTypes` / `CFBundleDocumentTypes` / `UTImportedTypeDeclarations`。
- `app_sandbox=true` 仍生效；唤起字符串通过 Apple Event 投递，无需额外 entitlements。

### Linux

- `linux/runner/my_application.cc`：
  - 新增 `gtk_application_get_windows` 单实例聚焦逻辑。
  - `local_command_line` 返回 `FALSE`，让 GApplication 继续 dispatch。
  - GApplication flags 改为 `G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN`。
- `linux/aria2down.desktop`：`MimeType=` 注册 `x-scheme-handler/aria2down`、`x-scheme-handler/magnet`、`application/x-bittorrent`、`application/metalink+xml`、`application/metalink4+xml`。
- `linux/aria2down-mime.xml`：自定义 shared-mime-info 包，显式声明 Metalink MIME 类型（部分发行版默认未带），含 `*.metalink` / `*.meta4` glob 与 XML magic。
- **安装到本机**：
  - 用户级（无需 root）：`./scripts/install_linux_associations.sh --user --bin "$(pwd)/build/linux/x64/release/bundle/aria2down" --set-default`
  - 系统级（需要 sudo）：`sudo ./scripts/install_linux_associations.sh --bin /opt/aria2down/aria2down --set-default`
  - `--bin` 会改写 `.desktop` 的 `Exec=` / `TryExec=` 为绝对路径；不指定时使用 `Exec=aria2down`（要求 PATH 里能找到）。
  - 卸载：`./scripts/uninstall_linux_associations.sh [--user]`
- AppImage 构建（`scripts/package_desktop.sh`）：使用完整 `linux/aria2down.desktop` + `aria2down-mime.xml`，配合 AppImageLauncher 可自动注册关联。
- 也可以手动用 `xdg-mime default aria2down.desktop x-scheme-handler/magnet` 等命令逐项指定默认处理器。

### Windows

- `windows/runner/main.cpp`：在 `wWinMain` 入口调用 `SendAppLinkToInstance(L"aria2down")`，把第二个进程的命令行 deep link 投递给已运行实例并自退出（单实例 + app_links 集成）。
- **MSIX 打包发行**（推荐）：`pubspec.yaml#msix_config`
  - `protocol_activation: aria2down, magnet` 注册 URL 协议。
  - `file_extension: .torrent, .metalink, .meta4` 注册文件关联。
- **Portable / zip 发行**：MSIX 声明只在 MSIX 安装包里生效，zip 解压版需要另行写注册表。仓库提供 [scripts/register_windows_associations.ps1](../scripts/register_windows_associations.ps1)：
  ```powershell
  # 在 portable 解压目录里直接运行（默认用脚本同级 aria2down.exe）：
  PowerShell -ExecutionPolicy Bypass -File .\scripts\register_windows_associations.ps1
  # 或显式指定：
  .\scripts\register_windows_associations.ps1 -ExePath "D:\Apps\aria2down\aria2down.exe"
  # 卸载：
  .\scripts\register_windows_associations.ps1 -Unregister
  ```
  脚本写入的是 `HKCU\Software\Classes`（当前用户），不需要管理员；用 ProgId 形式（`aria2down.torrent.1` 等）注册 `.torrent` / `.metalink` / `.meta4` 与 `aria2down:` / `magnet:` 两个 URL Protocol；文件扩展只挂 `OpenWithProgids`，不抢系统当前默认（首次双击 Windows 会让用户确认）。

---

## 5. 测试方法

| 平台 | 测试命令 |
| --- | --- |
| Android | `adb shell am start -a android.intent.action.VIEW -d 'aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip'` |
| iOS Simulator | `xcrun simctl openurl booted 'aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip'` |
| macOS | `open 'aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip'` |
| Linux | `xdg-open 'aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip'` |
| Windows | 浏览器地址栏粘贴 `aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip` 并回车（需 MSIX 安装后） |

磁力链替换为 `magnet:?xt=urn:btih:<info-hash>` 同样可触发。

---

## 6. 与浏览器扩展的关系

| 通道 | 适用场景 | 优势 |
| --- | --- | --- |
| 浏览器扩展直接调 aria2 RPC（`extensions/chrome` `firefox`） | 已经在浏览器内 | 不依赖应用是否前台 |
| `aria2down://` 唤起 | 用户想要预填后再确认 / 修改 | 复用应用 UI、统一历史 |

两者并存：扩展默认用 RPC，但可改为把目标 URL 包装成 `aria2down://add?uri=…` 后 `chrome.tabs.create` / `window.open` 唤起本应用。
