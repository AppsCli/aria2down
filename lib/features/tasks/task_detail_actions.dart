import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/queue_uris.dart';
import '../../core/reveal_path.dart';
import '../../core/rpc_error_message.dart';
import '../../providers/aria2_daemon_provider.dart';
import '../../providers/task_refresh_provider.dart';

/// 任务详情底部操作栏。
class TaskDetailActionBar extends ConsumerWidget {
  const TaskDetailActionBar({
    super.key,
    required this.status,
    required this.onChanged,
  });

  final Map<String, dynamic> status;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final st = '${status['status'] ?? ''}';
    final gid = '${status['gid']}';

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
                    .remove(gid, force: true);
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
                  final r = await queueUrisToAria2(d.client, uris);
                  if (r.added == 0 && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.snackAllDuplicates)),
                    );
                    return;
                  }
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }
}
