import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../data/app_settings.dart';

const _kTrayAsset = 'assets/tray/tray.png';

Future<void> Function()? _exitHandler;

final _windowToTrayListener = _WindowToTrayListener();
final _trayClickListener = _TrayClickListener();

bool _closeToTray = true;
bool _minimizeToTray = false;
bool _shellReady = false;

String _showLabel = 'Show window';
String _exitLabel = 'Quit';
String _toolTip = 'aria2down';

bool _isDesktopOs() {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

Future<void> initDesktopShell() async {
  if (!_isDesktopOs()) return;

  try {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(_windowToTrayListener);

    await trayManager.setIcon(_kTrayAsset);
    await _rebuildTrayMenu();
    trayManager.addListener(_trayClickListener);
    _shellReady = true;
  } catch (e, st) {
    debugPrint('aria2down: 桌面托盘/窗口壳层初始化失败（应用仍将继续运行）: $e\n$st');
  }
}

void applyDesktopShellBehavior(AppSettings settings) {
  if (!_isDesktopOs()) return;
  _closeToTray = settings.closeToTray;
  _minimizeToTray = settings.minimizeToTray;
}

void updateDesktopTrayLabels({
  required String showWindowLabel,
  required String exitLabel,
  required String toolTip,
}) {
  _showLabel = showWindowLabel;
  _exitLabel = exitLabel;
  _toolTip = toolTip;
  if (_shellReady) {
    unawaited(_refreshTrayChrome());
  }
}

void registerDesktopExitHandler(Future<void> Function() handler) {
  _exitHandler = handler;
}

Future<void> nativeExitApp() async {
  exit(0);
}

Future<void> _refreshTrayChrome() async {
  try {
    await trayManager.setToolTip(_toolTip);
    await _rebuildTrayMenu();
  } catch (_) {}
}

Future<void> _rebuildTrayMenu() async {
  await trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(
          key: 'show',
          label: _showLabel,
          onClick: (_) => unawaited(_showMainWindow()),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit',
          label: _exitLabel,
          onClick: (_) => unawaited(_runExitFlow()),
        ),
      ],
    ),
  );
}

Future<void> _showMainWindow() async {
  await windowManager.show();
  await windowManager.focus();
}

Future<void> _runExitFlow() async {
  try {
    await trayManager.destroy();
  } catch (_) {}
  final h = _exitHandler;
  if (h != null) {
    await h();
  }
  await nativeExitApp();
}

class _WindowToTrayListener with WindowListener {
  @override
  void onWindowClose() {
    if (_closeToTray) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_runExitFlow());
    }
  }

  @override
  void onWindowMinimize() {
    if (_minimizeToTray) {
      unawaited(windowManager.hide());
    }
  }
}

class _TrayClickListener with TrayListener {
  @override
  void onTrayIconMouseUp() {
    unawaited(_showMainWindow());
  }
}
