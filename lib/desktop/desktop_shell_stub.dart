import '../data/app_settings.dart';
import 'desktop_shell_types.dart';

Future<void> initDesktopShell({bool startMinimized = false}) async {}

void applyDesktopShellBehavior(AppSettings settings) {}

void updateDesktopTrayLabels(DesktopTrayLabels labels) {}

void updateDesktopTrayCallbacks(DesktopTrayCallbacks callbacks) {}

void updateDesktopTrayToolTip(String toolTip) {}

void registerDesktopExitHandler(Future<void> Function() handler) {}

Future<void> nativeExitApp() async {}

Future<void> showDesktopWindow() async {}
