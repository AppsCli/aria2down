import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/settings_repository.dart';
import 'desktop/desktop_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 提前读取设置：桌面端需要在窗口可见前决定是否静默启动到托盘。
  bool startMinimized = false;
  try {
    final settings = await SettingsRepository.load();
    startMinimized = settings.startMinimized;
  } catch (_) {}
  await initDesktopShell(startMinimized: startMinimized);
  runApp(const ProviderScope(child: Aria2downApp()));
}
