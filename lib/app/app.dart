import 'package:flutter/material.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_settings_provider.dart';
import '../providers/aria2_daemon_provider.dart';
import 'app_lifecycle_refresh.dart';
import 'daemon_error_screen.dart';
import 'desktop_integration.dart';
import 'desktop_shortcuts.dart';
import 'incoming_link_listener.dart';
import 'mobile_background_binding.dart';
import 'router.dart';
import 'theme.dart';
import 'tray_exit_binding.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final r = createAppRouter();
  ref.onDispose(r.dispose);
  return r;
});

/// daemon 启动期间显示的全屏 Loading：应用 logo 圆形容器 + 圆环 + 提示文字。
///
/// 比之前的「裸 CircularProgressIndicator + 一行文字」更有"应用正在准备资源"
/// 的仪式感；用 surfaceContainerLow 卡片让构图有重心。
class _DaemonLoadingScreen extends StatelessWidget {
  const _DaemonLoadingScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(
                              alpha: 0.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: scheme.primary,
                          ),
                        ),
                        Icon(
                          Icons.cloud_download_outlined,
                          color: scheme.primary,
                          size: 36,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'aria2down',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Aria2downApp extends ConsumerWidget {
  const Aria2downApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    return settingsAsync.when(
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAria2downTheme(Brightness.light),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAria2downTheme(Brightness.light),
        home: Scaffold(body: Center(child: Text('$e'))),
      ),
      data: (settings) {
        final router = ref.watch(_routerProvider);
        final daemon = ref.watch(aria2DaemonProvider);
        return AppLifecycleRefresh(
          child: DesktopIntegration(
            child: daemon.when(
              loading: () => MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'aria2down',
                locale: settings.localeOrNull,
                themeMode: settings.themeMode,
                theme: buildAria2downTheme(Brightness.light),
                darkTheme: buildAria2downTheme(Brightness.dark),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Builder(
                  builder: (ctx) {
                    final l = AppLocalizations.of(ctx)!;
                    return _DaemonLoadingScreen(
                      message: settings.isRemote
                          ? l.loadingRemoteAria2
                          : l.loadingAria2,
                    );
                  },
                ),
              ),
              error: (e, _) => MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'aria2down',
                locale: settings.localeOrNull,
                themeMode: settings.themeMode,
                theme: buildAria2downTheme(Brightness.light),
                darkTheme: buildAria2downTheme(Brightness.dark),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: DaemonErrorScreen(error: e),
              ),
              data: (_) => MaterialApp.router(
                debugShowCheckedModeBanner: false,
                title: 'aria2down',
                locale: settings.localeOrNull,
                themeMode: settings.themeMode,
                theme: buildAria2downTheme(Brightness.light),
                darkTheme: buildAria2downTheme(Brightness.dark),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
                builder: (context, child) {
                  return IncomingLinkListener(
                    router: router,
                    child: TrayExitBinding(
                      router: router,
                      child: MobileBackgroundBinding(
                        router: router,
                        child: DesktopShortcuts(
                          onOpenSettings: () => router.go('/settings'),
                          onOpenAdd: () => router.go('/add'),
                          child: child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
