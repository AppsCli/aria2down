# 从源码构建 aria2c（已废弃，见 ADR-010）

> **本文档已被 ADR-010 废弃。**
>
> aria2down 自 ADR-010 起本机模式只剩 [`LibraryDaemon`](../lib/aria2/daemon/library_daemon.dart)（FFI 内嵌 libaria2）。`aria2c` 子进程引擎、对应的 `scripts/build_aria2.sh` / `scripts/stage_aria2c.sh` 等 staging 流程、`assets/android/<abi>/aria2c` 二进制 placeholder、`bin/native_messaging_host.dart` / `bin/rpc_add_uri.dart` 等依赖 `rpc.secret` 的命令行工具都已经从源码中整体移除。
>
> **需要从源码编译什么？**
>
> - **libaria2 静态库（FFI 默认引擎）**：见 [BUILD_LIBARIA2.md](BUILD_LIBARIA2.md)；对应脚本 `scripts/build_libaria2_<platform>.sh`。
> - **外部 aria2c 二进制（远程 RPC 模式连接）**：请直接安装系统包（`apt install aria2` / `brew install aria2` / `pacman -S aria2` 等），然后在 aria2down 设置页切换为「远程 RPC」并填入对应 endpoint + secret。
>
> 历史完整内容见 git 历史中的本文件。
