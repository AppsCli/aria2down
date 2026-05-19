# 手动 QA 清单（发版前）

与 [docs/RELEASE.md](RELEASE.md) 配合使用。自动化覆盖见 `flutter test` 与 CI。

## 通用（任意引擎）

- [ ] 首次启动：daemon 就绪，任务列表可刷新
- [ ] 新建 HTTP(S) 任务并完成下载；重复 URI 被跳过
- [ ] 暂停 / 继续 / 删除 / 任务详情操作栏
- [ ] 设置：全局限速「立即应用」、导入/导出 JSON
- [ ] 快捷键：⌘/Ctrl+R 刷新、⌘/Ctrl+N 新建、⌘/Ctrl+, 设置

## 平台 × 引擎矩阵（ADR-007）

> 每个交叉点至少跑 1 次：①启动 → ②`addUri` 完成下载 → ③切引擎 → ④再启动一次。

| 平台 | 内嵌库（默认） | aria2c 子进程 | 远程 RPC |
| --- | --- | --- | --- |
| macOS | [ ] universal libaria2.a 装载、事件流正常 | [ ] 设置切换到子进程，`stage_aria2c.sh` 后重启 | [ ] 连接 NAS / Linux aria2 |
| Linux | [ ] x86_64 libaria2.a 装载 | [ ] `apt install aria2` 或本地编译后切换 | [ ] 同上 |
| Windows | [ ] mingw libaria2.a 装载 | [ ] choco/`stage_windows_aria2.ps1` 后切换 | [ ] 同上 |
| Android | [ ] arm64-v8a 装载（API 21+） | [ ] NDK 二进制 + 前台 Service 模式 | [ ] 同上 |
| iOS | [ ] device arm64 装载，前台下载完成 | n/a（沙盒禁用） | [ ] 同上 |
| Web | n/a | n/a | [ ] 浏览器中连接远程 aria2 |

### 引擎切换验证

- [ ] 设置 → 本机引擎 在「内嵌库 / 子进程」之间切换后 daemon 自动重建（`ref.invalidate`），列表立即恢复
- [ ] 关闭「失败时自动回退到子进程」后，使用未链接 libaria2 的构建会显示 `engineInitFailed` 错误页（不会静默回退）
- [ ] 关于页 / 任务详情中 RPC 端口字段在库模式下显示 `embedded://aria2/local` 占位

## 扩展（可选）

- [ ] Chrome：右键链接/页面发送到 aria2，角标 OK
- [ ] 选项页：剪贴板导入 RPC JSON（仅当连接模式为远程 / 引擎为子进程时显示「复制 RPC 配置」入口）

## 桌面打包

- [ ] dmg / tar.gz / zip 与 MSIX 产物正常启动，库模式默认生效；缺少 prebuilt 时回退到包内 `aria2c` 二进制
- [ ] 托盘：关闭到托盘、恢复窗口（若已启用）
