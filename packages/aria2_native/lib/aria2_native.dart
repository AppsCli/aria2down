/// Dart FFI entry point for the aria2_native plugin.
///
/// Public surface is intentionally narrow: callers should go through the
/// higher-level `Aria2NativeSession` (defined here) rather than touching the
/// raw bindings.
library;

export 'src/bindings.dart';
export 'src/exceptions.dart';
export 'src/loader.dart';
export 'src/session.dart';
