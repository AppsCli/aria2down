import 'desktop_shell_stub.dart'
    if (dart.library.html) 'desktop_shell_stub.dart'
    if (dart.library.io) 'desktop_shell_io.dart'
    as impl;

import '../data/app_settings.dart';
import 'desktop_shell_types.dart';

export 'desktop_shell_types.dart' show DesktopTrayCallbacks, DesktopTrayLabels;

Future<void> initDesktopShell({bool startMinimized = false}) =>
    impl.initDesktopShell(startMinimized: startMinimized);

void applyDesktopShellBehavior(AppSettings settings) =>
    impl.applyDesktopShellBehavior(settings);

void updateDesktopTrayLabels(DesktopTrayLabels labels) =>
    impl.updateDesktopTrayLabels(labels);

void updateDesktopTrayCallbacks(DesktopTrayCallbacks callbacks) =>
    impl.updateDesktopTrayCallbacks(callbacks);

void updateDesktopTrayToolTip(String toolTip) =>
    impl.updateDesktopTrayToolTip(toolTip);

void registerDesktopExitHandler(Future<void> Function() handler) =>
    impl.registerDesktopExitHandler(handler);

Future<void> nativeExitApp() => impl.nativeExitApp();

Future<void> showDesktopWindow() => impl.showDesktopWindow();
