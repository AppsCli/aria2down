import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform_hints.dart';
import '../providers/app_background_provider.dart';
import '../providers/task_refresh_provider.dart';

/// 应用从后台恢复时刷新任务列表。
class AppLifecycleRefresh extends ConsumerStatefulWidget {
  const AppLifecycleRefresh({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleRefresh> createState() =>
      _AppLifecycleRefreshState();
}

class _AppLifecycleRefreshState extends ConsumerState<AppLifecycleRefresh>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isMobilePlatform) {
      final inBackground =
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.detached;
      ref.read(appInBackgroundProvider.notifier).state = inBackground;
    }
    if (state == AppLifecycleState.resumed) {
      if (isMobilePlatform) {
        ref.read(appInBackgroundProvider.notifier).state = false;
      }
      ref.read(taskRefreshSignalProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
