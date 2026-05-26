import 'package:flutter/foundation.dart';

import 'aria2_exceptions.dart';
import 'rpc_transport.dart';

/// 装饰器：把 inner.call() 抛出的任何异常打到 Flutter 调试日志。
///
/// 之前 RPC 失败（如「任务详情概览 Tab 报 -1005」「`getPeers` 在非 BT 任务
/// 上 silently 返回错」「远程 RPC 鉴权失败」）在 UI 层往往只剩兜底文案，
/// 排查时必须临时插桩。此装饰器把方法名、aria2 错误码、消息与栈一并打到
/// `debugPrint`（`flutter run` 控制台 / `adb logcat` / Xcode console 均
/// 可见），rethrow 不改变控制流。
///
/// **不**记录 `params` 全文，只截取首 [_kMaxParamsPreview] 字符摘要——避免
/// 把 `aria2.addTorrent` 的 base64 种子（动辄数 MB）灌进日志。
final class Aria2LoggingTransport implements Aria2RpcTransport {
  Aria2LoggingTransport(this.inner, {required this.label});

  final Aria2RpcTransport inner;

  /// 区分不同 daemon / 调用方的标签（如 `library` / `local` / `remote` /
  /// `probe`）。直接拼进日志 `[aria2:<label>]`。
  final String label;

  static const int _kMaxParamsPreview = 160;

  @override
  Future<Object?> call(String method, List<dynamic> params) async {
    try {
      return await inner.call(method, params);
    } catch (e, st) {
      final codeStr = e is Aria2RpcException && e.code != null
          ? ' code=${e.code}'
          : '';
      // 已知的「软失败」（任务已被 purge / session 重置后查不到、远程 aria2 报
      // "No such download for GID"）从来不是 bug——UI 层有专门的 fallback
      // 路径（如 task_detail_page 切到历史快照）。把这些情况打成单行简讯，
      // 避免把整页 params 摘要 + 完整 Dart 栈喷到终端造成噪音，反而淹没真
      // 正需要排查的异常。
      if (_isExpectedSoftFailure(e)) {
        // 仅保留 method+code+message 摘要，足以在终端追溯调用上下文；
        // params 形态本来就是 [gid, ...]，gid 已经在 UI 层的 fallback 日志里
        // 再打一次（`task_detail` / `task_history_recorder` 等），不必重复。
        debugPrint('[aria2:$label] $method$codeStr → $e  (soft failure)');
        rethrow;
      }
      final paramsSummary = _summarizeParams(params);
      debugPrint('[aria2:$label] $method$codeStr → $e  params=$paramsSummary');
      // `debugPrintStack` 在 release 模式下也会被框架按节流策略丢弃，开发
      // 期能保留完整栈，发布版几乎无开销。
      debugPrintStack(stackTrace: st, label: '[aria2:$label] $method');
      rethrow;
    }
  }

  /// 是否属于「aria2 / FFI 已知的任务不存在」语义。
  ///
  /// - FFI 层：`Aria2RpcException.code == -1006`（`ARIA2_FFI_ERR_NOT_FOUND`）。
  /// - aria2 自带 RPC：消息含 `no such download` / `not found`（远程 / 子进程
  ///   模式）。
  ///
  /// 这类错误在以下场景属于**正常工作流**而非异常：
  /// 1. 从「历史」Tab 进入已被 `purgeDownloadResult` 的旧任务详情页；
  /// 2. 库引擎冷启动后 `downloadResults_` 为空，但旧 gid 仍在 WS 通知里推送；
  /// 3. UI 与 aria2 状态短暂不一致的轮询窗口（pause/remove 刚生效）。
  /// UI 已经各自 fallback；logging transport 只需要打单行简讯留痕。
  static bool _isExpectedSoftFailure(Object e) {
    if (e is! Aria2RpcException) return false;
    if (e.code == -1006) return true;
    final lower = e.message.toLowerCase();
    return lower.contains('no such download') || lower.contains('not found');
  }

  /// 按元素逐个判定是否需要占位，避免把整段 base64 种子先 `toString` 出来
  /// 再 substring（`addTorrent` 一次失败可能临时分配数 MB String）。
  static String _summarizeParams(List<dynamic> params) {
    if (params.isEmpty) return '[]';
    final buf = StringBuffer('[');
    var first = true;
    for (final p in params) {
      if (!first) buf.write(', ');
      first = false;
      buf.write(_summarizeOne(p));
      if (buf.length > _kMaxParamsPreview) {
        buf.write('…]');
        return buf.toString();
      }
    }
    buf.write(']');
    return buf.toString();
  }

  static String _summarizeOne(Object? value) {
    if (value is String) {
      if (value.length <= _kMaxParamsPreview) return '"$value"';
      return '<String len=${value.length}>';
    }
    if (value is List) {
      if (value.isEmpty) return '[]';
      // List 内逐元素也用同样规则，避免内嵌长字符串再次撑爆。
      final inner = StringBuffer('[');
      var first = true;
      for (final item in value) {
        if (!first) inner.write(', ');
        first = false;
        inner.write(_summarizeOne(item));
        if (inner.length > _kMaxParamsPreview) {
          inner.write('…]');
          return inner.toString();
        }
      }
      inner.write(']');
      return inner.toString();
    }
    if (value is Map) {
      return '<Map keys=${value.length}>';
    }
    final s = '$value';
    if (s.length <= _kMaxParamsPreview) return s;
    return '${s.substring(0, _kMaxParamsPreview)}…';
  }
}
