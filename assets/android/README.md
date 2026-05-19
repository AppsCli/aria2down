# Android aria2c 资源目录

将 NDK 交叉编译得到的 `aria2c` 按 ABI 放入：

```
assets/android/arm64-v8a/aria2c
assets/android/armeabi-v7a/aria2c
assets/android/x86_64/aria2c
```

可使用 `scripts/stage_android_aria2.sh` 从构建产物拷贝。未放置二进制时，应用会提示安装系统 aria2 或使用远程 RPC。

详见 [docs/ANDROID.md](../../docs/ANDROID.md)。
