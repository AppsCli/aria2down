# Prebuilt drop-zone for libaria2 + dependencies

Layout (populated by `scripts/build_libaria2_<platform>.sh`):

```
prebuilt/
├── macos/
│   └── universal/
│       ├── include/aria2/aria2.h
│       ├── libaria2.a              (lipo of arm64 + x86_64)
│       └── deps/*.a                (openssl, c-ares, sqlite3, zlib, ...)
├── linux/
│   └── x86_64/
│       ├── include/aria2/aria2.h
│       ├── libaria2.a
│       └── deps/*.a
├── windows/
│   └── x86_64/
│       ├── include/aria2/aria2.h
│       ├── libaria2.a
│       └── deps/*.a
├── android/
│   ├── armeabi-v7a/
│   ├── arm64-v8a/
│   └── x86_64/
│       (same shape as above)
└── ios/
    ├── arm64/                       (device)
    └── sim/                          (simulator universal)
```

If a platform/arch directory is missing, the plugin builds a stub-only
library: every FFI entry point returns `ARIA2_FFI_ERR_UNAVAILABLE`, letting
the Dart side fall back to the subprocess (`aria2c`) engine.
