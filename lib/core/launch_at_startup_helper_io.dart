import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

import '../data/app_settings.dart';

Future<void> applyLaunchAtStartup(AppSettings settings) async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return;
  }
  try {
    LaunchAtStartup.instance.setup(
      appName: 'aria2down',
      appPath: Platform.resolvedExecutable,
    );
    if (settings.launchAtStartup) {
      await LaunchAtStartup.instance.enable();
    } else {
      await LaunchAtStartup.instance.disable();
    }
  } catch (_) {
    // 部分平台/沙盒可能无权限，忽略。
  }
}
