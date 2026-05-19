import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format_utils.dart';
import '../../data/models/task_history_entry.dart';
import '../../data/task_history_repository.dart';
import '../../providers/task_history_provider.dart';

class TaskHistoryTab extends ConsumerWidget {
  const TaskHistoryTab({
    super.key,
    required this.searchQuery,
    required this.onRetry,
    required this.onRefresh,
  });

  final String searchQuery;
  final Future<void> Function(TaskHistoryEntry entry) onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(taskHistoryProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (entries) {
        final q = searchQuery.trim().toLowerCase();
        final filtered = q.isEmpty
            ? entries
            : entries
                  .where(
                    (e) =>
                        e.name.toLowerCase().contains(q) ||
                        e.gid.toLowerCase().contains(q),
                  )
                  .toList();

        if (filtered.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.3,
                  child: Center(child: Text(l10n.emptyHistory)),
                ),
              ],
            ),
          );
        }

        final dateFmt = DateFormat.yMMMd().add_Hm();

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = filtered[i];
              final progress = e.totalLength > 0
                  ? e.completedLength / e.totalLength
                  : 0.0;
              final canRetry = e.uris.isNotEmpty;

              return ListTile(
                onTap: () => context.push('/tasks/detail/${e.gid}'),
                title: Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e.status} · ${dateFmt.format(e.recordedAt.toLocal())}',
                    ),
                    Text(
                      '${formatBytes(e.completedLength)} / ${formatBytes(e.totalLength)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
                    if (e.errorMessage != null)
                      Text(
                        e.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: canRetry
                    ? IconButton(
                        tooltip: l10n.retry,
                        icon: const Icon(Icons.refresh),
                        onPressed: () => onRetry(e),
                      )
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

Future<void> confirmClearHistory(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.historyClearTitle),
      content: Text(l10n.historyClearMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.dialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.historyClearConfirm),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await TaskHistoryRepository.clear();
  ref.invalidate(taskHistoryProvider);
}
