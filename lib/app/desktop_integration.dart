import 'dart:async';

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/launch_at_startup_helper.dart';
import '../data/app_settings.dart';
import '../desktop/desktop_shell.dart';
import '../providers/app_settings_provider.dart';

/// 将设置同步到桌面托盘文案、关闭行为与开机自启。
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
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      updateDesktopTrayLabels(
        DesktopTrayLabels(
          showWindow: l10n.trayShowWindow,
          newTask: l10n.trayNewTask,
          pauseAll: l10n.trayPauseAll,
          resumeAll: l10n.trayResumeAll,
          openDownloads: l10n.trayOpenDownloads,
          quit: l10n.trayQuit,
          toolTip: l10n.trayToolTip,
        ),
      );
    }
  }
}
