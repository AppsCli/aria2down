// Exceptions emitted from the aria2_native plugin.

sealed class Aria2NativeException implements Exception {
  const Aria2NativeException(this.message, {this.code});
  final String message;
  final int? code;

  @override
  String toString() =>
      'Aria2NativeException(code: ${code ?? '-'}, message: $message)';
}

/// Thrown when the FFI plugin is loaded but compiled in stub mode (i.e. the
/// platform-specific `libaria2.a` was not bundled). The application should
/// fall back to the subprocess engine.
final class Aria2NativeUnavailableException extends Aria2NativeException {
  const Aria2NativeUnavailableException()
    : super(
        '当前 aria2_native 构建未链接 libaria2；请在设置中切换到子进程引擎或安装完整构建。',
        code: -1001,
      );
}

/// Thrown when a native call returns a non-zero error code.
final class Aria2NativeCallException extends Aria2NativeException {
  const Aria2NativeCallException(super.message, {required int super.code});
}
