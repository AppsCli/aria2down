import '../../core/format_utils.dart';
import '../../core/reveal_path.dart';

/// 已结束任务的本地快照（aria2 清空 stopped 列表后仍可查看）。
class TaskHistoryEntry {
  const TaskHistoryEntry({
    required this.gid,
    required this.name,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.recordedAt,
    this.dir,
    this.errorMessage,
    this.uris = const [],
    this.infoHash,
  });

  final String gid;
  final String name;
  final String status;
  final int totalLength;
  final int completedLength;
  final DateTime recordedAt;
  final String? dir;
  final String? errorMessage;
  final List<String> uris;
  final String? infoHash;

  factory TaskHistoryEntry.fromTellStatus(Map<String, dynamic> st) {
    // aria2 tellStatus 把 infoHash 放在响应根而不是 bittorrent 子结构里。
    // 不要求 `bittorrent` 子结构同时存在——magnet 任务在拿到 metadata 前就已经
    // 暴露 infoHash，提前持久化也方便后续去重。
    final ih = st['infoHash'];
    final hash = (ih is String && ih.isNotEmpty) ? ih : null;
    return TaskHistoryEntry(
      gid: '${st['gid'] ?? ''}',
      name: pickTaskName(st),
      status: '${st['status'] ?? 'unknown'}',
      totalLength: int.tryParse('${st['totalLength']}') ?? 0,
      completedLength: int.tryParse('${st['completedLength']}') ?? 0,
      recordedAt: DateTime.now().toUtc(),
      dir: st['dir'] as String?,
      errorMessage: _stringOrNull(st['errorMessage']),
      uris: extractUrisFromTask(st),
      infoHash: hash,
    );
  }

  static String? _stringOrNull(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return v;
  }

  Map<String, dynamic> toJson() => {
    'gid': gid,
    'name': name,
    'status': status,
    'totalLength': totalLength,
    'completedLength': completedLength,
    'recordedAt': recordedAt.toIso8601String(),
    'dir': dir,
    'errorMessage': errorMessage,
    'uris': uris,
    'infoHash': infoHash,
  };

  factory TaskHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TaskHistoryEntry(
      gid: '${json['gid'] ?? ''}',
      name: '${json['name'] ?? 'Task'}',
      status: '${json['status'] ?? 'unknown'}',
      // `totalLength`/`completedLength` 在 aria2 RPC 里以字符串十进制传输，
      // 历史文件可能由旧版本（int）/手动编辑（字符串/带空格）/RPC 直接转储
      // (字符串) 写入。与 [fromTellStatus] 保持一致地走 `int.tryParse`，避
      // 免 `as int?` 在字符串输入时抛 TypeError 让整条历史无法反序列化。
      totalLength: _parseInt(json['totalLength']),
      completedLength: _parseInt(json['completedLength']),
      recordedAt:
          DateTime.tryParse('${json['recordedAt']}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      dir: json['dir'] as String?,
      errorMessage: json['errorMessage'] as String?,
      uris:
          (json['uris'] as List<dynamic>?)
              ?.map((e) => '$e')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      infoHash: json['infoHash'] as String?,
    );
  }

  static int _parseInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v'.trim()) ?? 0;
  }

  Map<String, dynamic> toRetryTaskShape() => {
    'gid': gid,
    'status': status,
    'dir': dir,
    'totalLength': '$totalLength',
    'completedLength': '$completedLength',
    'files': [
      for (final u in uris)
        {
          'uris': [
            {'uri': u},
          ],
        },
    ],
    if (infoHash != null) 'bittorrent': {'infoHash': infoHash},
  };

  /// 合成一个**接近 `tellStatus` 响应**的 Map，供任务详情页在 aria2 已经
  /// 找不到该任务（例如被 purge、库引擎重启清空 session）时作为只读快照
  /// 兜底——比单一的 "加载失败" 全屏页友好得多。
  ///
  /// 字段限制：history 不存「每文件进度 / connections / downloadSpeed」等
  /// 动态数据，详情页 Overview/Torrent Tab 仅展示已持久化的部分；动态字段
  /// 会显示为 0 / 空，与 aria2 把任务从 `downloadResults_` 清空后再查询的
  /// 表现一致。
  Map<String, dynamic> toDetailShape() => {
    'gid': gid,
    'status': status,
    'totalLength': '$totalLength',
    'completedLength': '$completedLength',
    if (dir != null) 'dir': dir,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'files': [
      {
        'index': '1',
        // 用 history 持久化的 `name` 充当 path——`pickTaskName` 没有 uri
        // 时退到 path 末尾，确保 AppBar 标题不会变成 "Task" 占位。
        'path': name,
        'length': '$totalLength',
        'completedLength': '$completedLength',
        'selected': 'true',
        'uris': [
          for (final u in uris) {'uri': u, 'status': 'used'},
        ],
      },
    ],
    if (infoHash != null) ...{
      'infoHash': infoHash,
      'bittorrent': {
        if (name.isNotEmpty) 'info': {'name': name},
      },
    },
  };
}
