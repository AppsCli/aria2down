import 'dart:async';

import 'bindings.dart';

/// Lazy singleton accessor for [Aria2NativeBindings]. Once resolved, the
/// underlying dynamic library handle is cached.
class Aria2NativeLoader {
  Aria2NativeLoader._();
  static Aria2NativeBindings? _cached;

  /// Loads (or returns cached) bindings. May throw on platforms where the
  /// plugin is not registered. Callers should wrap in try/catch and fall
  /// back to the subprocess engine.
  static FutureOr<Aria2NativeBindings> load() {
    final cached = _cached;
    if (cached != null) return cached;
    final b = Aria2NativeBindings(openAria2NativeLibrary());
    _cached = b;
    return b;
  }

  /// Resets the cache. Intended for tests only.
  static void resetForTesting() {
    _cached = null;
  }
}
