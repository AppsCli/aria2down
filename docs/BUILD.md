# aria2 编译指南（aria2down）

本文档说明如何从子模块 `third_party/aria2` 在本机构建 `aria2c`，供桌面或后续打包内嵌使用。

> 官方权威说明见：[`third_party/aria2/README.rst`](../third_party/aria2/README.rst)  
> 在线手册：<https://aria2.github.io/manual/en/html/>

---

## 1. 通用步骤（autotools）

在子模块目录中：

```bash
cd third_party/aria2
autoreconf -i          # 若从 git 克隆且尚未生成 configure
./configure
make -j"$(nproc)"
```

成功后，可执行文件位于 **`src/aria2c`**。

静态链接（减小运行时依赖，便于分发）：

```bash
./configure ARIA2_STATIC=yes
make -j"$(nproc)"
```

---

## 2. macOS

### 2.1 依赖（Homebrew 示例）

```bash
brew install autoconf automake libtool pkg-config gettext \
  openssl libssh2 c-ares libxml2 sqlite cppunit
```

### 2.2 编译

```bash
cd third_party/aria2
autoreconf -i
./configure
make -j"$(sysctl -n hw.ncpu)"
```

亦可参考上游 `makerelease-osx.mk`。若 HTTPS 证书校验失败，可按官方 README 使用 `--with-ca-bundle` 或运行时 `--ca-certificate`。

### 2.3 开发调试

将生成的 `src/aria2c` 所在目录加入 `PATH`，或复制到 `/usr/local/bin`，**aria2down** 会通过 `BinaryResolver` 自动发现。

---

## 3. Linux（Debian / Ubuntu）

### 3.1 依赖

```bash
sudo apt-get install -y build-essential autoconf automake libtool \
  libssl-dev libssh2-1-dev libc-ares-dev libxml2-dev zlib1g-dev \
  libsqlite3-dev libcppunit-dev gettext autopoint
```

### 3.2 CA 证书（HTTPS）

Debian/Ubuntu 常见：

```bash
./configure --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
make -j"$(nproc)"
```

---

## 4. Windows（交叉编译）

推荐参考子模块内 **`Dockerfile.mingw`**，在 Linux 上使用 MinGW-w64 交叉编译；或在 Windows 上按官方 README「Cross-compiling Windows binary」配置工具链。

产出 **`aria2c.exe`** 后，可放入 Flutter Windows 打包目录，由应用随包分发（后续在 `PLAN` Phase 3 落地）。

---

## 5. Android

参考 **`third_party/aria2/Dockerfile.android`** 与 **`README.android`**，使用 NDK 交叉编译各 ABI，产出二进制后续放入 Flutter `assets/`（见 `PLAN` Phase 4）。

---

## 6. 与 aria2down 的衔接

| 阶段 | 说明 |
| --- | --- |
| 当前开发 | 本机 `PATH` 中存在 `aria2c` 即可启动应用内嵌的 [LocalDaemon](../lib/aria2/daemon/local_daemon.dart) |
| 同目录分发 | 将构建好的 `aria2c`（或 Windows 下的 `aria2c.exe`）放在 **与 Flutter 桌面应用主可执行文件同一目录**（例如 `build/macos/Build/Products/Release/*.app/Contents/MacOS/`、`build/linux/.../bundle/`、`build/windows/.../` 内与 `aria2down.exe` 并列），[BinaryResolver](../lib/aria2/binary/binary_resolver.dart) 会优先于 `PATH` 发现该文件（仍低于设置页中的显式路径覆盖） |
| 脚本 | `flutter build` 之后可用 [`scripts/stage_aria2c.sh`](../scripts/stage_aria2c.sh) 将本机编译的 `aria2c` 拷入上述目录；[`scripts/package_desktop.sh`](../scripts/package_desktop.sh) 在 `build/dist/` 生成 macOS `.dmg`、Linux `tar.gz`、Windows `zip`（内嵌二进制需在打包前自行 `stage_aria2c` 或 CI 拷贝） |
| CI | [`.github/workflows/flutter.yml`](../.github/workflows/flutter.yml) 在 `analyze-test` 通过后执行 **`linux-release-bundle`**：`flutter build linux --release`，将 `apt` 安装的 `/usr/bin/aria2c` 复制到 `bundle/`，并上传 **`aria2down-linux-amd64-bundle`** artifact（便于发版前取包；生产环境仍建议静态链接或自行校验依赖）。 |
| 后续 | 将各平台构建产物纳入 CI / 安装包脚本，在打包阶段自动拷贝 |

---

## 7. 许可证

aria2 为 **GPLv2+**；与本项目 `LICENSE` 一致。分发修改后的二进制须遵守相同许可证并提供对应源码获取方式。
