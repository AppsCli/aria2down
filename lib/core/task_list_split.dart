// 把 aria2 `tellStopped` 返回的混合列表按 status 拆成两路：成功完成 vs
// 被停止（error / removed / 其他）。
//
// 之前任务列表只有一个「已停止」Tab，把 `complete` / `error` / `removed`
// 全混在一起；用户找上次下完的文件要先翻一堆 .torrent 解析失败、加错链接
// 的报错记录。拆 Tab 后这两个 helper 给 [TaskListPage] 的 `_completedView`
// / `_stoppedView` getter 提供分流逻辑，同时保留 `_stopped` 字段本身作为
// 共享数据源（分页加载 + history 落库都仍走完整列表）。
//
// 抽到 `lib/core/` 顶级是为了单测：widget state 私有 getter 难直接 expect，
// 纯函数好测。

List<Map<String, dynamic>> filterCompletedTasks(
  List<Map<String, dynamic>> stoppedAll,
) {
  return [
    for (final t in stoppedAll)
      if ('${t['status'] ?? ''}' == 'complete') t,
  ];
}

/// 与 [filterCompletedTasks] 互补：返回原列表里 **不是** `complete` 的任务。
///
/// 兼容口径：status 为空 / 未知字符串时落入「已停止」一侧，避免任务被两边
/// 同时丢掉。aria2 RPC 当前定义的 stopped 子状态有 `complete` / `error` /
/// `removed`，未来新增 status 不应破坏可见性。
List<Map<String, dynamic>> filterStoppedTasks(
  List<Map<String, dynamic>> stoppedAll,
) {
  return [
    for (final t in stoppedAll)
      if ('${t['status'] ?? ''}' != 'complete') t,
  ];
}
