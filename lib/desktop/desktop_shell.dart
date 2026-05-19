import 'desktop_shell_stub.dart'
    if (dart.library.html) 'desktop_shell_stub.dart'
    if (dart.library.io) 'desktop_shell_io.dart'
    as impl;

import '../data/app_settings.dart';

Future<void> initDesktopShell() => impl.initDesktopShell();

void applyDesktopShellBehavior(AppSettings settings) =>
    impl.applyDesktopShellBehavior(settings);

void updateDesktopTrayLabels({
  required String showWindowLabel,
  required String exitLabel,
  required String toolTip,
}) => impl.updateDesktopTrayLabels(
  showWindowLabel: showWindowLabel,
  exitLabel: exitLabel,
  toolTip: toolTip,
);

void registerDesktopExitHandler(Future<void> Function() handler) =>
    impl.registerDesktopExitHandler(handler);

Future<void> nativeExitApp() => impl.nativeExitApp();
