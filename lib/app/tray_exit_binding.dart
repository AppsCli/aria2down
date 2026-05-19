import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../desktop/desktop_shell.dart';
import '../providers/app_settings_provider.dart';
import '../providers/aria2_daemon_provider.dart';

/// 在 [ProviderScope] 下注册托盘「退出」前需执行的逻辑（停止本地 aria2）。
class TrayExitBinding extends ConsumerStatefulWidget {
  const TrayExitBinding({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TrayExitBinding> createState() => _TrayExitBindingState();
}

class _TrayExitBindingState extends ConsumerState<TrayExitBinding> {
  var _registered = false;

  @override
  Widget build(BuildContext context) {
    if (!_registered) {
      _registered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        registerDesktopExitHandler(() async {
          final settings = ref.read(appSettingsProvider).valueOrNull;
          if (settings?.connectionMode == ConnectionMode.remote) {
            try {
              final d = await ref.read(aria2DaemonProvider.future);
              await d.stop();
            } catch (_) {}
            return;
          }
          try {
            final d = await ref.read(aria2DaemonProvider.future);
            await d.stop();
          } catch (_) {}
        });
      });
    }
    return widget.child;
  }
}
