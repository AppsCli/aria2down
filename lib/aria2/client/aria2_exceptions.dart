/// Exceptions for aria2 integration.
sealed class Aria2Exception implements Exception {
  const Aria2Exception(this.message);
  final String message;

  @override
  String toString() => 'Aria2Exception: $message';
}

final class Aria2RpcException extends Aria2Exception {
  const Aria2RpcException(super.message, {this.code});

  /// aria2 error code when available.
  final int? code;

  @override
  String toString() => 'Aria2RpcException(code: $code, message: $message)';
}

final class Aria2TransportException extends Aria2Exception {
  const Aria2TransportException(super.message, {this.cause});

  final Object? cause;

  @override
  String toString() => 'Aria2TransportException: $message (cause: $cause)';
}

final class Aria2DaemonException extends Aria2Exception {
  const Aria2DaemonException(super.message, {this.exitCode});

  final int? exitCode;

  @override
  String toString() =>
      'Aria2DaemonException(exitCode: $exitCode, message: $message)';
}

final class Aria2DaemonTimeoutException extends Aria2Exception {
  const Aria2DaemonTimeoutException() : super('aria2 RPC 在超时时间内未就绪。');
}

/// Web 端仅支持远程 RPC，无法启动本机子进程。
final class Aria2WebLocalUnsupportedException extends Aria2Exception {
  const Aria2WebLocalUnsupportedException()
    : super('Web 端仅支持远程 RPC，请在设置中切换连接方式。');
}
