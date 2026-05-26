import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/reveal_path.dart';
import '../../core/rpc_error_message.dart';
import '../../providers/aria2_daemon_provider.dart';
import '../../providers/task_refresh_provider.dart';

/// 任务详情底部操作栏。
class TaskDetailActionBar extends ConsumerWidget {
  const TaskDetailActionBar({
    super.key,
    required this.gid,
    required this.status,
    required this.onChanged,
  });

  /// 来自路由参数 `/tasks/detail/:gid`，永远是有效字符串。
  /// **不要**从 [status] 取 gid——如果 `tellStatus` 返回空 Map（库模式下任务
  /// 已被 purge），`status['gid']` 会是 null，`'${null}'` 变成字符串
  /// "null"，FFI 拿到非法 GID 抛 -1004。
  final String gid;
  final Map<String, dynamic> status;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final st = '${status['status'] ?? ''}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (st == 'active' || st == 'waiting')
              FilledButton.tonalIcon(
                onPressed: () => _run(context, ref, l10n, () async {
                  await ref.read(aria2DaemonProvider).value!.client.pause(gid);
                }),
                icon: const Icon(Icons.pause),
                label: Text(l10n.taskActionPause),
              ),
            if (st == 'paused')
              FilledButton.tonalIcon(
                onPressed: () => _run(context, ref, l10n, () async {
                  await ref
                      .read(aria2DaemonProvider)
                      .value!
                      .client
                      .unpause(gid);
                }),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.taskActionResume),
              ),
            if (st == 'active')
              OutlinedButton.icon(
                onPressed: () => _run(context, ref, l10n, () async {
                  await ref
                      .read(aria2DaemonProvider)
                      .value!
                      .client
                      .forcePause(gid);
                }),
                icon: const Icon(Icons.pause_circle_outline),
                label: Text(l10n.taskActionForcePause),
              ),
            OutlinedButton.icon(
              onPressed: () => _run(context, ref, l10n, () async {
                await ref
                    .read(aria2DaemonProvider)
                    .value!
                    .client
                    .removeTask(gid, status: st);
                if (context.mounted) context.pop();
              }),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.delete),
            ),
            if (st == 'error' || st == 'complete')
              OutlinedButton.icon(
                onPressed: () => _run(context, ref, l10n, () async {
                  final uris = extractUrisFromTask(status);
                  if (uris.isEmpty) return;
                  final d = ref.read(aria2DaemonProvider).value;
                  if (d == null) return;
                  // 单任务重试：原任务的 `files[].uris[]` 是同一资源的镜像，
                  // 必须用一次 addUri([all]) 让 aria2 当作同一任务的多个镜像；
                  // 不要走 queueUrisToAria2（那是面向「N 条独立链接 → N 个独立
                  // 任务」的剪贴板场景）。`dir` 沿用原任务以避免落到默认目录。
                  final opts = <String, dynamic>{};
                  final dir = status['dir'];
                  if (dir is String && dir.isNotEmpty) opts['dir'] = dir;
                  await d.client.addUri(
                    uris,
                    options: opts.isEmpty ? null : opts,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.snackAdded)));
                  }
                }),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      onChanged();
      ref.read(taskRefreshSignalProvider.notifier).state++;
    } catch (e, st) {
      // 详情底部按钮（暂停/恢复/删除/重试）失败：除 Aria2LoggingTransport
      // 的 RPC 行日志外，再补一条带 gid 上下文，便于关联 console 与 UI。
      debugPrint('[task_detail_actions] $gid action failed: $e');
      debugPrintStack(stackTrace: st, label: 'task_detail_actions');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }
}
