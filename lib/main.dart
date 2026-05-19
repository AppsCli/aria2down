import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/tray_exit_binding.dart';
import 'desktop/desktop_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopShell();
  runApp(const ProviderScope(child: TrayExitBinding(child: Aria2downApp())));
}
