/// 桌面托盘菜单回调集合。任一字段为 `null` 时对应菜单项不出现。
class DesktopTrayCallbacks {
  const DesktopTrayCallbacks({
    this.onShowWindow,
    this.onExit,
    this.onPauseAll,
    this.onResumeAll,
    this.onOpenDownloads,
    this.onNewTask,
  });

  final Future<void> Function()? onShowWindow;
  final Future<void> Function()? onExit;
  final Future<void> Function()? onPauseAll;
  final Future<void> Function()? onResumeAll;
  final Future<void> Function()? onOpenDownloads;
  final Future<void> Function()? onNewTask;
}

/// 托盘菜单与提示的本地化文案。
class DesktopTrayLabels {
  const DesktopTrayLabels({
    required this.showWindow,
    required this.newTask,
    required this.pauseAll,
    required this.resumeAll,
    required this.openDownloads,
    required this.quit,
    required this.toolTip,
  });

  final String showWindow;
  final String newTask;
  final String pauseAll;
  final String resumeAll;
  final String openDownloads;
  final String quit;
  final String toolTip;
}
