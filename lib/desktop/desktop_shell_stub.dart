import '../data/app_settings.dart';

Future<void> initDesktopShell() async {}

void applyDesktopShellBehavior(AppSettings settings) {}

void updateDesktopTrayLabels({
  required String showWindowLabel,
  required String exitLabel,
  required String toolTip,
}) {}

void registerDesktopExitHandler(Future<void> Function() handler) {}

Future<void> nativeExitApp() async {}
