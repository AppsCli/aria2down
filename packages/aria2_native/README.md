# aria2_native

Flutter FFI plugin: Dart bindings to a thin C ABI shim (`src/aria2_ffi.{h,cc}`)
around the C++ libaria2 API (`third_party/aria2/src/includes/aria2/aria2.h`).

Used by aria2down to run aria2 in-process on macOS / Linux / Windows / Android /
iOS instead of spawning a separate `aria2c` subprocess.

## Layout

```
packages/aria2_native/
├── lib/                   Dart bindings (manually maintained; mirrors ffigen output)
├── src/                   Cross-platform C/C++ shim sources
├── android/               Android Gradle + CMake bridge
├── ios/                   iOS pod (links to a prebuilt libaria2.a XCFramework)
├── macos/                 macOS pod (links to a prebuilt libaria2.a fat archive)
├── linux/                 Linux CMake (links to prebuilt libaria2.a or system aria2)
├── windows/               Windows CMake (mingw / MSVC artifact)
└── prebuilt/              Drop-zone for libaria2 + dependencies static archives,
                           populated by scripts/build_libaria2_<platform>.sh.
```

## Stub mode

If no prebuilt `libaria2.a` is found for the target platform/arch, the shim
compiles **stub-only**: every FFI entry point returns
`ARIA2_FFI_ERR_UNAVAILABLE`. The Dart side reports this through
`Aria2NativeUnavailableException`, allowing the application to fall back to the
subprocess engine.

## Updating bindings

The Dart bindings in `lib/aria2_bindings.dart` are kept by hand to avoid making
`ffigen` a hard dev dependency for everyone. The header
`src/aria2_ffi.h` is the source of truth — when extending it, mirror new
symbols in the Dart file (and ideally regenerate with ffigen against the same
header to spot drift).
