// 验证设置页「本机引擎」分组在本机连接模式下可见，且可在内嵌库/子进程之间切换。
import 'package:aria2down/features/settings/settings_page.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'settings.connection_mode': 'local',
      'settings.local_engine': 'library',
      'settings.fallback_to_subprocess': true,
    });
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('本机模式下展示「本机引擎」分组与回退开关', (tester) async {
    await pumpSettings(tester);
    expect(find.text('本机引擎'), findsOneWidget);
    expect(find.text('内嵌库（libaria2）'), findsOneWidget);
    expect(find.text('aria2c 子进程'), findsOneWidget);
    expect(find.text('失败时自动回退到子进程'), findsOneWidget);
  });

  testWidgets('选择子进程引擎后隐藏「自动回退」开关', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('aria2c 子进程'));
    await tester.pumpAndSettle();
    expect(find.text('失败时自动回退到子进程'), findsNothing);
  });
}
