# 发版说明（v0.1.0 及后续）

本文档供维护者在打 **Git 标签**、上传 **GitHub Release** 或分发安装包前自查。与 [PLAN.md](../PLAN.md) 中 **P3-08** 对应。

---

## 1. 版本与变更记录

1. 确认 [CHANGELOG.md](../CHANGELOG.md) 中 **`[Unreleased]`** 已清空或已合并进即将发布的版本节。
2. 将 **`[0.1.0] - 未发布`** 改为 **`[0.1.0] - YYYY-MM-DD`**（打 tag 当日）。
3. 核对根目录 **`pubspec.yaml`** 的 `version:` 与标签一致（例如 **`0.1.0+1`**：`0.1.0` 为对外版本，`+` 后为构建号）。

---

## 2. 静态检查与测试

```bash
./scripts/validate_release.sh
# 或等价于：
# ./scripts/prepare_release.sh   # 内含 validate，并打印打 tag 提示
# ./scripts/tag_release.sh       # validate + 打印 git tag / gh release 命令
```

合并到默认分支前，CI（`.github/workflows/flutter.yml`）应全部通过。维护者还可在 GitHub **Actions → Release prep**（`release.yml`）手动触发校验与 Linux bundle 构建。

---

## 3. 各平台构建产物

| 平台 | 推荐命令 / 说明 |
| --- | --- |
| Linux | `./scripts/build_desktop.sh linux` → `./scripts/stage_aria2c.sh linux /usr/bin/aria2c`（路径按本机调整）→ `./scripts/package_desktop.sh linux`（或 `SKIP_BUILD=1`） |
| macOS | 同上，`macos`；**`.dmg`** 需在 macOS 上执行（`hdiutil`） |
| Windows | 同上，`windows`；**zip** 见 `package_desktop.sh`；拷贝 aria2：`./scripts/stage_windows_aria2.ps1`；**MSIX** 见 [MSIX.md](MSIX.md) |

**CI 预构建**：在 GitHub Actions 成功运行后，从 **`linux-release-bundle`** 作业下载 artifact **`aria2down-linux-amd64-bundle`**（已内含 apt 提供的 `aria2c`，仅作试跑/内测；生产分发建议静态链接或自行审计依赖）。

---

## 4. Git 标签与 GitHub Release（可选）

```bash
# 例：仅当 CHANGELOG 与 pubspec 已对齐 0.1.0 后执行
git tag -a v0.1.0 -m "aria2down v0.1.0 MVP"
git push origin v0.1.0
```

在 GitHub 上创建 **Release**，正文可摘录 **CHANGELOG** 中该版本小节，并附上各平台构建产物（或说明从 CI artifact 获取 Linux 包）。

```bash
./scripts/create_github_release.sh v0.1.0
# 或先 ./scripts/print_release_notes.sh 预览说明
```

---

## 5. 平台注意事项

- **macOS**：未签名的 `.app`/`.dmg` 可能被 **Gatekeeper** 拦截；正式分发需 **Apple 开发者签名与公证**（超出当前 MVP 文档范围）。
- **Windows**：可执行文件与 **VC++ 运行库**、**aria2c.exe** 及其依赖需一并验证；**msix** 见规划 **P3-05**。
- **GPL**：随包提供 **aria2** 与 **本项目** 的源码获取方式（例如子模块地址与仓库 URL）。

---

## 6. 发布后

- 在 [PLAN.md](../PLAN.md) 将 **P3-08** 标为 **✅**，并追加 **项目进度日志**（类型可用 `release`）。
- 将 [CHANGELOG.md](../CHANGELOG.md) 下一版本 **`[Unreleased]`** 预置为空或小标题，便于继续积累。
