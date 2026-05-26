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
                  height: MediaQuery.sizeOf(context).height * 0.55,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer
                                .withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.history,
                            size: 40,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.emptyHistory,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final dateFmt = DateFormat.yMMMd().add_Hm();
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

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
              // 用状态色 + 状态图标的左侧徽章替代单调 ListTile，与任务列表一致。
              final Color statusColor;
              final IconData statusIcon;
              switch (e.status) {
                case 'complete':
                  statusColor = const Color(0xFF2E7D32);
                  statusIcon = Icons.check_circle;
                  break;
                case 'error':
                  statusColor = scheme.error;
                  statusIcon = Icons.error;
                  break;
                case 'removed':
                  statusColor = scheme.onSurfaceVariant;
                  statusIcon = Icons.delete_forever;
                  break;
                default:
                  statusColor = scheme.primary;
                  statusIcon = Icons.history;
              }

              return InkWell(
                onTap: () => context.push('/tasks/detail/${e.gid}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(statusIcon, color: statusColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateFmt.format(e.recordedAt.toLocal()),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                backgroundColor: scheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  statusColor,
                                ),
                                minHeight: 4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${formatBytes(e.completedLength)} / ${formatBytes(e.totalLength)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (e.errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  e.errorMessage!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canRetry)
                        IconButton(
                          tooltip: l10n.retry,
                          icon: const Icon(Icons.refresh),
                          onPressed: () => onRetry(e),
                        ),
                      IconButton(
                        tooltip: l10n.historyDeleteTooltip,
                        icon: const Icon(Icons.delete_outline),
                        // 历史 Tab 的「删除」是纯本地动作：很多条目对应的
                        // gid 已被 aria2 `purgeDownloadResult` 出 session，
                        // 走 `removeDownloadResult` 会一直回 -1006。所以这
                        // 里直接调 `TaskHistoryRepository.deleteByGid`，让
                        // 用户能擦掉看上去删不掉的历史。详情页历史快照
                        // banner 上的删除按钮共用此实现。
                        onPressed: () =>
                            confirmDeleteHistoryEntry(context, ref, e.gid),
                      ),
                    ],
                  ),
                ),
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

/// 弹确认对话框删除单条历史记录。
///
/// 这是**纯本地**操作：与 aria2 session 无关，磁盘上的下载文件保留，aria2
/// 队列也不受影响。返回是否真的删了一条（用于详情页 banner 在删除后自动
/// 关闭页面）。
Future<bool> confirmDeleteHistoryEntry(
  BuildContext context,
  WidgetRef ref,
  String gid,
) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.historyDeleteTitle),
      content: Text(l10n.historyDeleteMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.dialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.historyDeleteConfirm),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final removed = await TaskHistoryRepository.deleteByGid(gid);
  ref.invalidate(taskHistoryProvider);
  if (removed && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.historyDeleteSnack)));
  }
  return removed;
}
