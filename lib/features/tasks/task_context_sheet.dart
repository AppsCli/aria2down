import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_deep_link.dart';
import '../../core/reveal_path.dart';
import '../../core/rpc_error_message.dart';
import '../../core/task_share.dart';
import '../../providers/aria2_daemon_provider.dart';
import '../../providers/task_refresh_provider.dart';

/// 任务长按快捷操作（复制、打开目录、暂停/继续、详情等）。
Future<void> showTaskContextSheet(
  BuildContext context, {
  required Map<String, dynamic> task,
  Future<void> Function()? onOpenFolder,
  VoidCallback? onAfterAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _TaskContextSheet(
      task: task,
      onOpenFolder: onOpenFolder,
      onAfterAction: onAfterAction,
    ),
  );
}

class _TaskContextSheet extends ConsumerWidget {
  const _TaskContextSheet({
    required this.task,
    this.onOpenFolder,
    this.onAfterAction,
  });

  final Map<String, dynamic> task;
  final Future<void> Function()? onOpenFolder;
  final VoidCallback? onAfterAction;

  Future<void> _runRpc(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      onAfterAction?.call();
      ref.read(taskRefreshSignalProvider.notifier).state++;
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final gid = '${task['gid'] ?? ''}';
    final st = '${task['status'] ?? ''}';
    final uris = extractUrisFromTask(task);
    final canOpen = onOpenFolder != null && resolveRevealPath(task) != null;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.taskContextViewDetail),
              onTap: () {
                Navigator.pop(context);
                context.push('/tasks/detail/$gid');
              },
            ),
            if (canOpen)
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(l10n.openFolder),
                onTap: () async {
                  Navigator.pop(context);
                  await onOpenFolder!();
                },
              ),
            if (st == 'active' || st == 'waiting')
              ListTile(
                leading: const Icon(Icons.pause),
                title: Text(l10n.taskActionPause),
                onTap: () => _runRpc(context, ref, l10n, () async {
                  await ref.read(aria2DaemonProvider).value!.client.pause(gid);
                }),
              ),
            if (st == 'paused')
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(l10n.taskActionResume),
                onTap: () => _runRpc(context, ref, l10n, () async {
                  await ref
                      .read(aria2DaemonProvider)
                      .value!
                      .client
                      .unpause(gid);
                }),
              ),
            if (st == 'active')
              ListTile(
                leading: const Icon(Icons.pause_circle_outline),
                title: Text(l10n.taskActionForcePause),
                onTap: () => _runRpc(context, ref, l10n, () async {
                  await ref
                      .read(aria2DaemonProvider)
                      .value!
                      .client
                      .forcePause(gid);
                }),
              ),
            ListTile(
              leading: const Icon(Icons.tag_outlined),
              title: Text(l10n.taskDetailFieldGid),
              subtitle: Text(gid, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: gid));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
            if (uris.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: Text(l10n.copyTaskUris),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: uris.join('\n')));
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.taskShare),
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: buildTaskShareText(task)),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
            if (uris.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(l10n.copyAddTaskLink),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: buildInAppAddPathForUris(uris)),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
