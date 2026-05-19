import '../client/aria2_client.dart';
import '../client/ws_listener.dart';

/// 抽象：本地子进程或远程 RPC 端点。
abstract class Aria2Daemon {
  int get rpcPort;
  String get rpcSecret;
  Uri get rpcHttpUri;
  Uri get rpcWebSocketUri;

  Aria2Client get client;

  /// WebSocket 通知（不可用则为 `null`，任务列表将回退轮询）。
  ///
  /// 远程/本机子进程：[WsAria2Notifier]；
  /// 内嵌库：基于 libaria2 事件回调的等价 [Aria2NotificationSource]。
  Aria2NotificationSource? get wsNotifier => null;

  /// 本机 aria2 日志路径（仅 [LocalDaemon] 有值）。
  String? get logFilePath => null;

  Future<void> start();

  Future<void> stop({bool force = false});
}
