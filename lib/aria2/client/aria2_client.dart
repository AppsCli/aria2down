import 'package:flutter/foundation.dart' show debugPrint;

import 'aria2_exceptions.dart';
import 'rpc_methods.dart';
import 'rpc_transport.dart';

/// aria2 JSON-RPC 客户端（当前仅 HTTP；WebSocket 见 [WsAria2Notifier]）。
final class Aria2Client {
  Aria2Client({required Aria2RpcTransport transport}) : _t = transport;

  final Aria2RpcTransport _t;

  Future<Map<String, dynamic>> getVersion() async {
    final r = await _t.call(RpcMethods.getVersion, const <dynamic>[]) as Map;
    return Map<String, dynamic>.from(r);
  }

  /// 把 transport 返回的 `result` 期望为非空 String：transport 实现异常或被
  /// 中间人篡改时可能返回 null/非 String；此前用 `r! as String` 会抛
  /// `Null check operator used on a null value`/`TypeError`，文案对终端
  /// 用户不友好。统一改抛 [Aria2TransportException]，让 `formatRpcError`
  /// 能给出可读提示。
  String _expectGid(Object? r, String method) {
    if (r is String) return r;
    throw Aria2TransportException(
      '$method 返回意外结果：${r == null ? 'null' : r.runtimeType}',
    );
  }

  Future<String> addUri(
    List<String> uris, {
    Map<String, dynamic>? options,
  }) async {
    final r = await _t.call(RpcMethods.addUri, <dynamic>[
      uris,
      options ?? <String, dynamic>{},
    ]);
    return _expectGid(r, RpcMethods.addUri);
  }

  Future<String> addTorrent(
    String base64Torrent, {
    List<String>? uris,
    Map<String, dynamic>? options,
  }) async {
    final r = await _t.call(RpcMethods.addTorrent, <dynamic>[
      base64Torrent,
      uris ?? <String>[],
      options ?? <String, dynamic>{},
    ]);
    return _expectGid(r, RpcMethods.addTorrent);
  }

  Future<String> addMetalink(
    String base64Metalink, {
    Map<String, dynamic>? options,
  }) async {
    final r = await _t.call(RpcMethods.addMetalink, <dynamic>[
      base64Metalink,
      options ?? <String, dynamic>{},
    ]);
    return _expectGid(r, RpcMethods.addMetalink);
  }

  Future<void> pause(String gid) async {
    await _t.call(RpcMethods.pause, <dynamic>[gid]);
  }

  Future<void> forcePause(String gid) async {
    await _t.call(RpcMethods.forcePause, <dynamic>[gid]);
  }

  Future<void> unpause(String gid) async {
    await _t.call(RpcMethods.unpause, <dynamic>[gid]);
  }

  Future<void> pauseAll() async {
    await _t.call(RpcMethods.pauseAll, const <dynamic>[]);
  }

  Future<void> unpauseAll() async {
    await _t.call(RpcMethods.unpauseAll, const <dynamic>[]);
  }

  Future<void> forcePauseAll() async {
    await _t.call(RpcMethods.forcePauseAll, const <dynamic>[]);
  }

  Future<void> purgeDownloadResult() async {
    await _t.call(RpcMethods.purgeDownloadResult, const <dynamic>[]);
  }

  Future<void> removeDownloadResult(String gid) async {
    await _t.call(RpcMethods.removeDownloadResult, <dynamic>[gid]);
  }

  Future<void> remove(String gid, {bool force = false}) async {
    await _t.call(force ? RpcMethods.forceRemove : RpcMethods.remove, <dynamic>[
      gid,
    ]);
  }

  /// 删除任务：进行中走 [remove]（force），已结束走 [removeDownloadResult]。
  ///
  /// [status] 来自 `tellStatus` / 列表项的 `status` 字段；未知时先 forceRemove，
  /// 失败再尝试 removeDownloadResult（兼容远程 RPC 与库引擎）。
  ///
  /// 两次尝试都失败时抛**第二次**的异常，但**第一次**的异常会用 `debugPrint`
  /// 留痕——之前实现里第一次失败的错误（可能是网络/鉴权）被静默吃掉，使得
  /// 上层看到的报错与真正根因脱节。
  Future<void> removeTask(String gid, {String? status}) async {
    if (_isStoppedTaskStatus(status)) {
      await removeDownloadResult(gid);
      return;
    }
    try {
      await remove(gid, force: true);
    } catch (firstError) {
      // 关键：第一次错误必须留痕。之前实现 catch(_) 直接吞，下游只能拿到
      // 第二次（removeDownloadResult）的失败信息，看不到真正的原始原因
      // （网络/鉴权/超时等）。这里走 debugPrint 而不是 logging transport，
      // 因为 forceRemove 走的就是 transport，单纯 RPC 异常已经被 logging
      // transport 打印过一遍；这里再补一条「将回退到 removeDownloadResult」
      // 的上下文行，让两条日志可关联。
      debugPrint(
        '[aria2] removeTask($gid) forceRemove failed, falling back to '
        'removeDownloadResult: $firstError',
      );
      await removeDownloadResult(gid);
    }
  }

  static bool _isStoppedTaskStatus(String? status) {
    switch (status) {
      case 'complete':
      case 'error':
      case 'removed':
        return true;
      default:
        return false;
    }
  }

  Future<Map<String, dynamic>> tellStatus(
    String gid, {
    List<String>? keys,
  }) async {
    final params = keys == null ? <dynamic>[gid] : <dynamic>[gid, keys];
    final r = await _t.call(RpcMethods.tellStatus, params) as Map;
    return Map<String, dynamic>.from(r);
  }

  Future<List<Map<String, dynamic>>> getFiles(String gid) async {
    final r =
        await _t.call(RpcMethods.getFiles, <dynamic>[gid]) as List<dynamic>;
    return r
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// BitTorrent 任务的 peers 列表；非 BT 任务可能返回错误或空列表。
  Future<List<Map<String, dynamic>>> getPeers(String gid) async {
    final r =
        await _t.call(RpcMethods.getPeers, <dynamic>[gid]) as List<dynamic>;
    return r
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> tellActive({List<String>? keys}) async {
    final params = keys == null ? <dynamic>[] : <dynamic>[keys];
    final r = await _t.call(RpcMethods.tellActive, params) as List<dynamic>;
    return r
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> tellWaiting({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) async {
    final params = keys == null
        ? <dynamic>[offset, num]
        : <dynamic>[offset, num, keys];
    final r = await _t.call(RpcMethods.tellWaiting, params) as List<dynamic>;
    return r
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> tellStopped({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) async {
    final params = keys == null
        ? <dynamic>[offset, num]
        : <dynamic>[offset, num, keys];
    final r = await _t.call(RpcMethods.tellStopped, params) as List<dynamic>;
    return r
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<GlobalStat> getGlobalStat() async {
    final r = await _t.call(RpcMethods.getGlobalStat, const <dynamic>[]) as Map;
    return GlobalStat.fromJson(Map<String, dynamic>.from(r));
  }

  Future<Map<String, String>> getGlobalOption() async {
    final r =
        await _t.call(RpcMethods.getGlobalOption, const <dynamic>[]) as Map;
    return r.map((k, v) => MapEntry('$k', '$v'));
  }

  Future<void> changeGlobalOption(Map<String, String> options) async {
    await _t.call(RpcMethods.changeGlobalOption, <dynamic>[options]);
  }

  Future<Map<String, String>> getOption(String gid) async {
    final r = await _t.call(RpcMethods.getOption, <dynamic>[gid]) as Map;
    return r.map((k, v) => MapEntry('$k', '$v'));
  }

  Future<void> changeOption(String gid, Map<String, String> options) async {
    await _t.call(RpcMethods.changeOption, <dynamic>[gid, options]);
  }

  Future<void> shutdown({bool force = false}) async {
    await _t.call(
      force ? RpcMethods.forceShutdown : RpcMethods.shutdown,
      const <dynamic>[],
    );
  }
}

class GlobalStat {
  const GlobalStat({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.numActive,
    required this.numWaiting,
    required this.numStopped,
    required this.numStoppedTotal,
  });

  factory GlobalStat.fromJson(Map<String, dynamic> json) {
    int i(String k) => int.tryParse('${json[k]}') ?? 0;
    return GlobalStat(
      downloadSpeed: i('downloadSpeed'),
      uploadSpeed: i('uploadSpeed'),
      numActive: i('numActive'),
      numWaiting: i('numWaiting'),
      numStopped: i('numStopped'),
      numStoppedTotal: i('numStoppedTotal'),
    );
  }

  final int downloadSpeed;
  final int uploadSpeed;
  final int numActive;
  final int numWaiting;
  final int numStopped;
  final int numStoppedTotal;
}
