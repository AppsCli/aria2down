# aria2 本地补丁

上游子模块 [`third_party/aria2`](../../third_party/aria2) 保持干净（指向
`https://github.com/aria2/aria2`），Android 相关修改以 patch 形式存放在此目录。

| 补丁 | 作用 |
| --- | --- |
| `android-openssl-drbg-and-ssl-guards.patch` | Android OpenSSL DRBG 绕路（`Platform.cc` / `SimpleRandomizer.cc`）+ `LibsslTLSContext` null guard |

`scripts/build_libaria2_android_macos.sh`（及未来其他 `build_libaria2_*.sh`）
在交叉编译前对 worktree 副本执行 `patch -p1`。

升级 aria2 子模块后若 patch 冲突，请 `git -C third_party/aria2 pull` 后在本目录
用 `git diff` 重新生成补丁并更新此 README。
