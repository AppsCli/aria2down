# aria2_native changelog

## 0.1.0

- Initial scaffold: C ABI shim around libaria2 + Dart FFI bindings + high-level
  `Aria2NativeSession` with event stream.
- Stub-only build supported when no prebuilt `libaria2.a` is present (every
  FFI function returns `ARIA2_FFI_ERR_UNAVAILABLE`).
