# 浏览器扩展（P5-08）

Chrome / Chromium 扩展草案：通过 **JSON-RPC** 将右键链接发送到本机 aria2。

## 安装（开发者模式）

1. 打开 `chrome://extensions` → 开启「开发者模式」
2. 「加载已解压的扩展程序」→ 选择本目录下的 `chrome/`
3. 点击扩展图标或右键扩展 → **选项**，填写：
   - **JSON-RPC URL**：与 aria2down 设置一致，默认 `http://127.0.0.1:6800/jsonrpc`
   - **RPC secret**：与 `aria2.conf` / aria2down 本机 token 一致
   - 或在 aria2down **设置 → 复制扩展用 RPC 配置**，在选项页点 **Import from clipboard (JSON)**

## 使用

在任意网页 **右键链接** → **Send link to aria2**，或 **右键页面** → **Send this page to aria2**。Chrome 扩展图标上会短暂显示 **OK** / **!** 角标表示成功或失败。

## 限制

- 浏览器须能访问 RPC（通常仅 `127.0.0.1`；远程 RPC 需在 `host_permissions` 中扩展域名）
- aria2 需开启 RPC 且 `rpc-listen-all` / CORS 策略允许浏览器来源（本机调试可在 `aria2.conf` 中放宽）
- **Firefox**：`extensions/firefox/`（Manifest V2 草案；选项页同样支持剪贴板导入 RPC JSON）

## 应用内深链（GUI）

扩展不打开 aria2down 窗口。若要在 **桌面 GUI** 预填新建任务，见 [docs/DEEPLINKS.md](../docs/DEEPLINKS.md)（`/add?uri=`）。

## 与桌面端关系

扩展 **不依赖** aria2down 进程，直接与 aria2 对话。桌面端「远程模式」若监听同一端口，扩展与 GUI 可共用同一 daemon。
