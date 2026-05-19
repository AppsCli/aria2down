import 'launch_at_startup_helper_stub.dart'
    if (dart.library.io) 'launch_at_startup_helper_io.dart'
    as impl;

import '../data/app_settings.dart';

Future<void> applyLaunchAtStartup(AppSettings settings) =>
    impl.applyLaunchAtStartup(settings);
