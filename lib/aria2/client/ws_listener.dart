import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'aria2_exceptions.dart';

/// 通用通知源抽象：WebSocket（远程/子进程）与库模式都通过此接口暴露推送事件。
abstract class Aria2NotificationSource {
  Stream<Aria2RpcNotification> get notifications;

  Future<void> dispose();
}

/// WebSocket JSON-RPC：接收 aria2 主动推送的通知（如 `aria2.onDownloadComplete`）。
///
/// 请求仍建议走 [Aria2HttpTransport]，避免在 WS 上维护请求/响应配对状态。
class WsAria2Notifier implements Aria2NotificationSource {
  WsAria2Notifier({required Uri endpoint, required String secret})
    : _endpoint = endpoint,
      _secret = secret;

  final Uri _endpoint;
  final String _secret;
  WebSocketChannel? _channel;
  final _controller = StreamController<Aria2RpcNotification>.broadcast();

  @override
  Stream<Aria2RpcNotification> get notifications => _controller.stream;

  Future<void> connect() async {
    await disconnect();
    try {
      _channel = WebSocketChannel.connect(_endpoint);
      _channel!.stream.listen(
        _onMessage,
        onError: (Object e, StackTrace st) {
          if (!_controller.isClosed) {
            _controller.addError(
              Aria2TransportException('WebSocket 错误', cause: e),
              st,
            );
          }
        },
        onDone: () {},
        cancelOnError: false,
      );
    } catch (e, st) {
      Error.throwWithStackTrace(
        Aria2TransportException('无法连接 WebSocket', cause: e),
        st,
      );
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic>? map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>?;
    } catch (_) {
      return;
    }
    if (map == null) return;
    final method = map['method'] as String?;
    if (method == null) return;
    final params = map['params'];
    final gid = _firstGid(params);
    if (gid == null) return;
    final n = Aria2RpcNotification.parse(method, gid);
    if (n != null && !_controller.isClosed) {
      _controller.add(n);
    }
  }

  static String? _firstGid(Object? params) {
    if (params is List && params.isNotEmpty) {
      return params.first?.toString();
    }
    return null;
  }

  /// 通过 WS 发送一次 `aria2.getVersion` 以触发鉴权（部分版本可能需要）。
  Future<void> ping() async {
    final ch = _channel;
    if (ch == null) return;
    final msg = jsonEncode({
      'jsonrpc': '2.0',
      'id': 'ws-ping',
      'method': 'aria2.getVersion',
      'params': <dynamic>['token:$_secret'],
    });
    ch.sink.add(msg);
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}

sealed class Aria2RpcNotification {
  const Aria2RpcNotification(this.gid);
  final String gid;

  static Aria2RpcNotification? parse(String method, String gid) {
    return switch (method) {
      'aria2.onDownloadStart' => DownloadStartNotification(gid),
      'aria2.onDownloadPause' => DownloadPauseNotification(gid),
      'aria2.onDownloadStop' => DownloadStopNotification(gid),
      'aria2.onDownloadComplete' => DownloadCompleteNotification(gid),
      'aria2.onDownloadError' => DownloadErrorNotification(gid),
      'aria2.onBtDownloadComplete' => BtDownloadCompleteNotification(gid),
      _ => null,
    };
  }
}

final class DownloadStartNotification extends Aria2RpcNotification {
  const DownloadStartNotification(super.gid);
}

final class DownloadPauseNotification extends Aria2RpcNotification {
  const DownloadPauseNotification(super.gid);
}

final class DownloadStopNotification extends Aria2RpcNotification {
  const DownloadStopNotification(super.gid);
}

final class DownloadCompleteNotification extends Aria2RpcNotification {
  const DownloadCompleteNotification(super.gid);
}

final class DownloadErrorNotification extends Aria2RpcNotification {
  const DownloadErrorNotification(super.gid);
}

final class BtDownloadCompleteNotification extends Aria2RpcNotification {
  const BtDownloadCompleteNotification(super.gid);
}
