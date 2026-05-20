import 'package:aria2_native/aria2_native.dart';

import 'aria2_exceptions.dart';
import 'rpc_methods.dart';
import 'rpc_transport.dart';

/// 把 `Aria2Client` 期望的 JSON-RPC 调用翻译成对内嵌 libaria2 的 FFI 调用。
///
/// 这样 [Aria2Client] 与所有上层（Repository / UI / Provider）完全无感切换。
/// JSON-RPC 的 `params` 与返回值形态与 aria2c 网络层一致，参考
/// https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface
///
/// 真正的 FFI 调用发生在 [Aria2NativeSession] 内部的 worker isolate，
/// 这里只负责参数翻译与 await 结果。`onMutate` 钩子仍保留给外部调用方
/// 触发自定义动作（worker 自身已在每次变更后主动 kick 一次事件循环）。
final class Aria2InProcessTransport implements Aria2RpcTransport {
  Aria2InProcessTransport(this.session, {this.onMutate});

  final Aria2NativeSession session;

  /// 任何会改变 aria2 内部状态的 RPC（addUri / pause / remove 等）调用后触发。
  /// 主要用于让上层主动刷新 UI；worker 内部已经在变更后立即跑一次事件循环，
  /// 调用方不必再为缩短首字节延迟而手动驱动。
  final void Function()? onMutate;

  static const _kMutatingMethods = <String>{
    RpcMethods.addUri,
    RpcMethods.addTorrent,
    RpcMethods.addMetalink,
    RpcMethods.remove,
    RpcMethods.forceRemove,
    RpcMethods.pause,
    RpcMethods.forcePause,
    RpcMethods.pauseAll,
    RpcMethods.forcePauseAll,
    RpcMethods.unpause,
    RpcMethods.unpauseAll,
    RpcMethods.purgeDownloadResult,
    RpcMethods.removeDownloadResult,
    RpcMethods.changeGlobalOption,
    RpcMethods.changeOption,
  };

  @override
  Future<Object?> call(String method, List<dynamic> params) async {
    try {
      final result = await _dispatch(method, params);
      if (_kMutatingMethods.contains(method)) {
        onMutate?.call();
      }
      return result;
    } on Aria2NativeUnavailableException catch (e) {
      throw Aria2TransportException(e.message, cause: e);
    } on Aria2NativeCallException catch (e) {
      throw Aria2RpcException(e.message, code: e.code);
    }
  }

  Future<Object?> _dispatch(String method, List<dynamic> params) async {
    switch (method) {
      case RpcMethods.getVersion:
        return session.getVersion();

      case RpcMethods.addUri:
        final uris = _stringList(params, 0);
        final options = _stringMapOrNull(params, 1) ?? const <String, String>{};
        return session.addUri(uris, options: options);

      case RpcMethods.addTorrent:
        final torrent = _stringAt(params, 0);
        final uris = _stringList(params, 1, optional: true);
        final options = _stringMapOrNull(params, 2) ?? const <String, String>{};
        return session.addTorrent(torrent, webSeedUris: uris, options: options);

      case RpcMethods.addMetalink:
        final metalink = _stringAt(params, 0);
        final options = _stringMapOrNull(params, 1) ?? const <String, String>{};
        return session.addMetalink(metalink, options: options);

      case RpcMethods.remove:
        await session.remove(_stringAt(params, 0));
        return 'OK';
      case RpcMethods.forceRemove:
        await session.remove(_stringAt(params, 0), force: true);
        return 'OK';
      case RpcMethods.pause:
        await session.pause(_stringAt(params, 0));
        return 'OK';
      case RpcMethods.forcePause:
        await session.pause(_stringAt(params, 0), force: true);
        return 'OK';
      case RpcMethods.pauseAll:
        await session.pauseAll();
        return 'OK';
      case RpcMethods.forcePauseAll:
        await session.pauseAll(force: true);
        return 'OK';
      case RpcMethods.unpause:
        await session.unpause(_stringAt(params, 0));
        return 'OK';
      case RpcMethods.unpauseAll:
        await session.unpauseAll();
        return 'OK';

      case RpcMethods.purgeDownloadResult:
        await session.purgeDownloadResult();
        return 'OK';
      case RpcMethods.removeDownloadResult:
        await session.removeDownloadResult(_stringAt(params, 0));
        return 'OK';

      case RpcMethods.getFiles:
        return session.getFiles(_stringAt(params, 0));
      case RpcMethods.getPeers:
        return session.getPeers(_stringAt(params, 0));

      case RpcMethods.tellStatus:
        final gid = _stringAt(params, 0);
        final keys = _stringListOrNull(params, 1);
        return session.tellStatus(gid, keys: keys);

      case RpcMethods.tellActive:
        final keys = _stringListOrNull(params, 0);
        return session.tellActive(keys: keys);

      case RpcMethods.tellWaiting:
        final offset = _intAt(params, 0);
        final num = _intAt(params, 1);
        final keys = _stringListOrNull(params, 2);
        return session.tellWaiting(offset: offset, num: num, keys: keys);

      case RpcMethods.tellStopped:
        final offset = _intAt(params, 0);
        final num = _intAt(params, 1);
        final keys = _stringListOrNull(params, 2);
        return session.tellStopped(offset: offset, num: num, keys: keys);

      case RpcMethods.getGlobalStat:
        return session.getGlobalStat();
      case RpcMethods.getGlobalOption:
        return session.getGlobalOption();
      case RpcMethods.changeGlobalOption:
        final opts = _stringMapOrNull(params, 0) ?? const <String, String>{};
        await session.changeGlobalOption(opts);
        return 'OK';

      case RpcMethods.getOption:
        return session.getOption(_stringAt(params, 0));
      case RpcMethods.changeOption:
        final gid = _stringAt(params, 0);
        final opts = _stringMapOrNull(params, 1) ?? const <String, String>{};
        await session.changeOption(gid, opts);
        return 'OK';

      case RpcMethods.shutdown:
      case RpcMethods.forceShutdown:
        // 库模式下 daemon.stop() 会调用 session.close()。
        // 这里立即返回，让 Aria2Client.shutdown 路径不抛错。
        return 'OK';

      default:
        throw Aria2RpcException('库模式不支持的 RPC 方法：$method', code: -32601);
    }
  }

  // ----- 参数解析 ---------------------------------------------------------

  String _stringAt(List<dynamic> params, int index) {
    if (index >= params.length) {
      throw const Aria2RpcException('缺少必填参数', code: -32602);
    }
    final v = params[index];
    if (v is String) return v;
    throw Aria2RpcException(
      '参数 #$index 期望 String，实际：${v.runtimeType}',
      code: -32602,
    );
  }

  int _intAt(List<dynamic> params, int index) {
    if (index >= params.length) {
      throw const Aria2RpcException('缺少必填参数', code: -32602);
    }
    final v = params[index];
    if (v is int) return v;
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
    throw Aria2RpcException(
      '参数 #$index 期望 int，实际：${v.runtimeType}',
      code: -32602,
    );
  }

  List<String> _stringList(
    List<dynamic> params,
    int index, {
    bool optional = false,
  }) {
    if (index >= params.length) {
      if (optional) return const <String>[];
      throw const Aria2RpcException('缺少必填参数', code: -32602);
    }
    final v = params[index];
    if (v is List) return v.map((e) => e.toString()).toList();
    throw Aria2RpcException(
      '参数 #$index 期望 List，实际：${v.runtimeType}',
      code: -32602,
    );
  }

  List<String>? _stringListOrNull(List<dynamic> params, int index) {
    if (index >= params.length) return null;
    final v = params[index];
    if (v == null) return null;
    if (v is List) return v.map((e) => e.toString()).toList();
    return null;
  }

  Map<String, String>? _stringMapOrNull(List<dynamic> params, int index) {
    if (index >= params.length) return null;
    final v = params[index];
    if (v == null) return null;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val.toString()));
    }
    return null;
  }
}
