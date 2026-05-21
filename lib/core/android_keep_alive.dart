import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 前台服务通知：保持本机 aria2 在后台运行并实时显示进度。
///
/// 同时暴露 [controlEvents] 用于接收通知按钮（暂停全部 / 继续全部 /
/// 显示主窗口）触发的控制指令。
abstract final class AndroidKeepAlive {
  static const _method = MethodChannel('cloud.iothub.aria2down/keep_alive');
  static const _events = EventChannel(
    'cloud.iothub.aria2down/keep_alive_control',
  );

  static bool get _available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 启动前台服务。可在启动时传入初始统计；后续用 [update] 刷新。
  static Future<void> start({
    int downSpeed = 0,
    int upSpeed = 0,
    int active = 0,
    int waiting = 0,
    KeepAliveLabels? labels,
  }) async {
    if (!_available) return;
    try {
      await _method.invokeMethod<void>(
        'start',
        _payload(
          downSpeed: downSpeed,
          upSpeed: upSpeed,
          active: active,
          waiting: waiting,
          labels: labels,
        ),
      );
    } catch (_) {}
  }

  /// 仅刷新前台服务的进度通知（不重启服务）。
  static Future<void> update({
    required int downSpeed,
    required int upSpeed,
    required int active,
    required int waiting,
    KeepAliveLabels? labels,
  }) async {
    if (!_available) return;
    try {
      await _method.invokeMethod<void>(
        'update',
        _payload(
          downSpeed: downSpeed,
          upSpeed: upSpeed,
          active: active,
          waiting: waiting,
          labels: labels,
        ),
      );
    } catch (_) {}
  }

  /// 停止前台服务。
  static Future<void> stop() async {
    if (!_available) return;
    try {
      await _method.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// 通知按钮触发的控制信号流：`pause_all` / `resume_all` / `show_window`。
  static Stream<String> get controlEvents {
    if (!_available) return const Stream<String>.empty();
    return _events.receiveBroadcastStream().map((e) => '$e');
  }

  static Map<String, dynamic> _payload({
    required int downSpeed,
    required int upSpeed,
    required int active,
    required int waiting,
    KeepAliveLabels? labels,
  }) {
    final m = <String, dynamic>{
      'downSpeed': downSpeed,
      'upSpeed': upSpeed,
      'active': active,
      'waiting': waiting,
    };
    if (labels != null) {
      m['title'] = labels.title;
      m['labelShow'] = labels.show;
      m['labelPause'] = labels.pause;
      m['labelResume'] = labels.resume;
      m['labelQuit'] = labels.quit;
    }
    return m;
  }
}

class KeepAliveLabels {
  const KeepAliveLabels({
    required this.title,
    required this.show,
    required this.pause,
    required this.resume,
    required this.quit,
  });

  final String title;
  final String show;
  final String pause;
  final String resume;
  final String quit;
}
