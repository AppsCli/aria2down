import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/task_refresh_provider.dart';

/// 桌面全局快捷键。
class DesktopShortcuts extends ConsumerWidget {
  const DesktopShortcuts({
    super.key,
    required this.child,
    this.onOpenSettings,
    this.onOpenAdd,
  });

  final Widget child;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenAdd;

  static bool get enabled {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) return child;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyR, meta: true): _RefreshIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, control: true):
            _RefreshIntent(),
        SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _SettingsIntent(),
        SingleActivator(LogicalKeyboardKey.comma, control: true):
            _SettingsIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, meta: true): _AddIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true): _AddIntent(),
      },
      child: Actions(
        actions: {
          _RefreshIntent: CallbackAction<_RefreshIntent>(
            onInvoke: (_) {
              ref.read(taskRefreshSignalProvider.notifier).state++;
              return null;
            },
          ),
          _SettingsIntent: CallbackAction<_SettingsIntent>(
            onInvoke: (_) {
              onOpenSettings?.call();
              return null;
            },
          ),
          _AddIntent: CallbackAction<_AddIntent>(
            onInvoke: (_) {
              onOpenAdd?.call();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
}

class _AddIntent extends Intent {
  const _AddIntent();
}
