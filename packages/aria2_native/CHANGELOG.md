# aria2_native changelog

## 0.2.0

- **Worker-isolate runtime**: every libaria2 FFI call now executes in a
  dedicated worker isolate spawned by `Aria2NativeWorker.spawn`. The main
  isolate (Flutter UI thread) is never blocked by
  `aria2::run(RUN_ONCE) → eventPoll_->poll(refreshInterval=1s)`, which could
  previously freeze the UI for up to a second per tick. As a consequence, all
  `Aria2NativeSession` methods are now `Future<T>`. The event callback runs in
  the worker via `NativeCallable.listener` and is forwarded to the main
  isolate as a `SendPort` message. Mutating RPCs (`addUri`, `pause`, …) kick
  the worker's run loop immediately so user actions stay snappy.

## 0.1.0

- Initial scaffold: C ABI shim around libaria2 + Dart FFI bindings + high-level
  `Aria2NativeSession` with event stream.
- Stub-only build supported when no prebuilt `libaria2.a` is present (every
  FFI function returns `ARIA2_FFI_ERR_UNAVAILABLE`).
