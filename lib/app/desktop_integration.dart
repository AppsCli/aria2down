import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/launch_at_startup_helper.dart';
import '../data/app_settings.dart';
import '../desktop/desktop_shell.dart';
import '../providers/app_settings_provider.dart';

/// 将设置同步到桌面外壳：关闭/最小化行为与开机自启。
///
/// 托盘菜单文案的本地化在 [TrayExitBinding] 内完成（那里位于 [MaterialApp]
/// 之下，可以读取 [AppLocalizations]）。此处只处理与 l10n 无关的副作用。
class DesktopIntegration extends ConsumerStatefulWidget {
  const DesktopIntegration({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopIntegration> createState() => _DesktopIntegrationState();
}

class _DesktopIntegrationState extends ConsumerState<DesktopIntegration> {
  @override
  Widget build(BuildContext context) {
    ref.listen(appSettingsProvider, (prev, next) {
      next.whenData(_apply);
    });
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    if (settings != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _apply(settings));
    }
    return widget.child;
  }

  void _apply(AppSettings settings) {
    applyDesktopShellBehavior(settings);
    unawaited(applyLaunchAtStartup(settings));
  }
}
