import '../aria2/client/aria2_client.dart';
import '../aria2/client/ws_listener.dart';
import '../data/models/task_history_entry.dart';
import '../data/task_history_repository.dart';
import 'task_list_keys.dart';

/// 将已结束任务写入本地历史（WS 事件 + stopped 列表轮询）。
final class TaskHistoryRecorder {
  TaskHistoryRecorder(this._client);

  final Aria2Client _client;
  final _recordedGids = <String>{};

  Future<void> onNotification(Aria2RpcNotification n) async {
    final record = switch (n) {
      DownloadCompleteNotification() => true,
      DownloadErrorNotification() => true,
      DownloadStopNotification() => true,
      BtDownloadCompleteNotification() => true,
      _ => false,
    };
    if (!record) return;
    await _recordGid(n.gid);
  }

  Future<void> onStoppedList(List<Map<String, dynamic>> stopped) async {
    final pending = <String>[];
    for (final t in stopped) {
      final gid = '${t['gid'] ?? ''}';
      if (gid.isEmpty || _recordedGids.contains(gid)) continue;
      pending.add(gid);
    }
    for (final gid in pending) {
      await _recordGid(gid);
    }
  }

  Future<void> _recordGid(String gid) async {
    if (gid.isEmpty || _recordedGids.contains(gid)) return;
    try {
      final st = await _client.tellStatus(gid, keys: kTaskHistoryTellKeys);
      final entry = TaskHistoryEntry.fromTellStatus(st);
      await TaskHistoryRepository.upsert(entry);
      _recordedGids.add(gid);
    } catch (_) {
      /* 任务可能已被 purge */
    }
  }
}
