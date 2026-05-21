import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../data/app_settings.dart';
import 'desktop_shell_types.dart';

const _kTrayAsset = 'assets/tray/tray.png';

Future<void> Function()? _exitHandler;
DesktopTrayCallbacks _cbs = const DesktopTrayCallbacks();

final _windowToTrayListener = _WindowToTrayListener();
final _trayClickListener = _TrayClickListener();

bool _closeToTray = true;
bool _minimizeToTray = false;
bool _shellReady = false;

DesktopTrayLabels _labels = const DesktopTrayLabels(
  showWindow: 'Show window',
  newTask: 'New download',
  pauseAll: 'Pause all',
  resumeAll: 'Resume all',
  openDownloads: 'Open downloads folder',
  quit: 'Quit',
  toolTip: 'aria2down',
);
String _toolTip = 'aria2down';

bool _isDesktopOs() {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

Future<void> initDesktopShell({bool startMinimized = false}) async {
  if (!_isDesktopOs()) return;

  try {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(_windowToTrayListener);

    await trayManager.setIcon(_kTrayAsset);
    await _rebuildTrayMenu();
    trayManager.addListener(_trayClickListener);
    _shellReady = true;

    if (startMinimized) {
      // 即便 launch_at_startup 让窗口已经显示，也立刻隐藏到托盘。
      unawaited(windowManager.hide());
    }
  } catch (e, st) {
    debugPrint('aria2down: 桌面托盘/窗口壳层初始化失败（应用仍将继续运行）: $e\n$st');
  }
}

void applyDesktopShellBehavior(AppSettings settings) {
  if (!_isDesktopOs()) return;
  _closeToTray = settings.closeToTray;
  _minimizeToTray = settings.minimizeToTray;
}

void updateDesktopTrayLabels(DesktopTrayLabels labels) {
  _labels = labels;
  _toolTip = labels.toolTip;
  if (_shellReady) {
    unawaited(_refreshTrayChrome());
  }
}

void updateDesktopTrayCallbacks(DesktopTrayCallbacks callbacks) {
  _cbs = callbacks;
  if (_shellReady) {
    unawaited(_rebuildTrayMenu());
  }
}

void updateDesktopTrayToolTip(String toolTip) {
  if (!_isDesktopOs() || !_shellReady) return;
  if (_toolTip == toolTip) return;
  _toolTip = toolTip;
  unawaited(trayManager.setToolTip(toolTip).catchError((_) {}));
}

void registerDesktopExitHandler(Future<void> Function() handler) {
  _exitHandler = handler;
}

Future<void> nativeExitApp() async {
  exit(0);
}

Future<void> showDesktopWindow() async {
  if (!_isDesktopOs()) return;
  await _showMainWindow();
}

Future<void> _refreshTrayChrome() async {
  try {
    await trayManager.setToolTip(_toolTip);
    await _rebuildTrayMenu();
  } catch (_) {}
}

Future<void> _rebuildTrayMenu() async {
  final items = <MenuItem>[
    MenuItem(
      key: 'show',
      label: _labels.showWindow,
      onClick: (_) => unawaited(_showMainWindow()),
    ),
    if (_cbs.onNewTask != null)
      MenuItem(
        key: 'add',
        label: _labels.newTask,
        onClick: (_) => unawaited(_runCallback(_cbs.onNewTask)),
      ),
    MenuItem.separator(),
    if (_cbs.onPauseAll != null)
      MenuItem(
        key: 'pause_all',
        label: _labels.pauseAll,
        onClick: (_) => unawaited(_runCallback(_cbs.onPauseAll)),
      ),
    if (_cbs.onResumeAll != null)
      MenuItem(
        key: 'resume_all',
        label: _labels.resumeAll,
        onClick: (_) => unawaited(_runCallback(_cbs.onResumeAll)),
      ),
    if (_cbs.onOpenDownloads != null)
      MenuItem(
        key: 'open_downloads',
        label: _labels.openDownloads,
        onClick: (_) => unawaited(_runCallback(_cbs.onOpenDownloads)),
      ),
    MenuItem.separator(),
    MenuItem(
      key: 'exit',
      label: _labels.quit,
      onClick: (_) => unawaited(_runExitFlow()),
    ),
  ];
  await trayManager.setContextMenu(Menu(items: items));
}

Future<void> _runCallback(Future<void> Function()? cb) async {
  if (cb == null) return;
  try {
    await cb();
  } catch (e, st) {
    debugPrint('aria2down: 托盘动作执行失败: $e\n$st');
  }
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

  @override
  void onTrayIconRightMouseUp() {
    unawaited(trayManager.popUpContextMenu().catchError((_) {}));
  }
}
