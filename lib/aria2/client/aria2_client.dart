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

  Future<String> addUri(
    List<String> uris, {
    Map<String, dynamic>? options,
  }) async {
    final r = await _t.call(RpcMethods.addUri, <dynamic>[
      uris,
      options ?? <String, dynamic>{},
    ]);
    return r! as String;
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
    return r! as String;
  }

  Future<String> addMetalink(
    String base64Metalink, {
    Map<String, dynamic>? options,
  }) async {
    final r = await _t.call(RpcMethods.addMetalink, <dynamic>[
      base64Metalink,
      options ?? <String, dynamic>{},
    ]);
    return r! as String;
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
