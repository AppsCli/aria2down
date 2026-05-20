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
import 'router.dart';
import 'theme.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final r = createAppRouter();
  ref.onDispose(r.dispose);
  return r;
});

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
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (ctx) {
                        final l = AppLocalizations.of(ctx)!;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              settings.isRemote
                                  ? l.loadingRemoteAria2
                                  : l.loadingAria2,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
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
                    child: DesktopShortcuts(
                      onOpenSettings: () => router.go('/settings'),
                      onOpenAdd: () => router.go('/add'),
                      child: child ?? const SizedBox.shrink(),
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
