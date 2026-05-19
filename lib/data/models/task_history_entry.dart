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
    final bt = st['bittorrent'];
    String? hash;
    if (bt is Map && bt['infoHash'] != null) {
      hash = '${bt['infoHash']}';
    }
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
      totalLength: json['totalLength'] as int? ?? 0,
      completedLength: json['completedLength'] as int? ?? 0,
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
}
