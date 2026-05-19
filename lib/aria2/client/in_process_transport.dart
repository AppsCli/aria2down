import 'package:aria2_native/aria2_native.dart';

import 'aria2_exceptions.dart';
import 'rpc_methods.dart';
import 'rpc_transport.dart';

/// 把 `Aria2Client` 期望的 JSON-RPC 调用翻译成对内嵌 libaria2 的 FFI 调用。
///
/// 这样 [Aria2Client] 与所有上层（Repository / UI / Provider）完全无感切换。
/// JSON-RPC 的 `params` 与返回值形态与 aria2c 网络层一致，参考
/// https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface
final class Aria2InProcessTransport implements Aria2RpcTransport {
  Aria2InProcessTransport(this.session);

  final Aria2NativeSession session;

  @override
  Future<Object?> call(String method, List<dynamic> params) async {
    try {
      return _dispatch(method, params);
    } on Aria2NativeUnavailableException catch (e) {
      throw Aria2TransportException(e.message, cause: e);
    } on Aria2NativeCallException catch (e) {
      throw Aria2RpcException(e.message, code: e.code);
    }
  }

  Object? _dispatch(String method, List<dynamic> params) {
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
        session.remove(_stringAt(params, 0));
        return 'OK';
      case RpcMethods.forceRemove:
        session.remove(_stringAt(params, 0), force: true);
        return 'OK';
      case RpcMethods.pause:
        session.pause(_stringAt(params, 0));
        return 'OK';
      case RpcMethods.forcePause:
        session.pause(_stringAt(params, 0), force: true);
        return 'OK';
      case RpcMethods.pauseAll:
        session.pauseAll();
        return 'OK';
      case RpcMethods.forcePauseAll:
        session.pauseAll(force: true);
        return 'OK';
      case RpcMethods.unpause:
        session.unpause(_stringAt(params, 0));
        return 'OK';
      case RpcMethods.unpauseAll:
        session.unpauseAll();
        return 'OK';

      case RpcMethods.purgeDownloadResult:
        session.purgeDownloadResult();
        return 'OK';
      case RpcMethods.removeDownloadResult:
        session.removeDownloadResult(_stringAt(params, 0));
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
        session.changeGlobalOption(opts);
        return 'OK';

      case RpcMethods.getOption:
        return session.getOption(_stringAt(params, 0));
      case RpcMethods.changeOption:
        final gid = _stringAt(params, 0);
        final opts = _stringMapOrNull(params, 1) ?? const <String, String>{};
        session.changeOption(gid, opts);
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
