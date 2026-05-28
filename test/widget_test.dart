import 'package:aria2down/data/app_settings.dart';
import 'package:aria2down/data/settings_repository.dart';
import 'package:aria2down/features/settings/settings_page.dart';
import 'package:aria2down/providers/app_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('设置页展示标题（中文）', (WidgetTester tester) async {
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
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('不再渲染独立的「保存」按钮（每次更改即生效）', (WidgetTester tester) async {
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
    // 之前桌面端有一个 FilledButton(child: Text('保存'))；移动端 bottomNavigationBar
    // 里也有一个。新行为下两处都该消失——下面这条找的是「文本恰好为‘保存’的
    // 任何 widget」，命中 0 个即说明 Save 按钮真的被拿掉了。
    expect(find.widgetWithText(FilledButton, '保存'), findsNothing);
  });

  testWidgets('切换主题偏好后立刻写盘，无需点保存', (WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 先确认默认 system；用 ProviderContainer 旁路 widget tree 拿 notifier。
    final initial = await container.read(appSettingsProvider.future);
    expect(initial.theme, AppThemePreference.system);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 点「深色」段：SegmentedButton 段在 Material 3 下渲染为内部的 _SegmentButton
    // widget；用文本匹配。
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    // 内存中的 provider 状态立刻更新——这是用户在 UI 上感知到「主题真的换了」
    // 的根因。
    final afterToggle = container.read(appSettingsProvider).valueOrNull;
    expect(afterToggle?.theme, AppThemePreference.dark);

    // 同时已经持久化到 SharedPreferences——下次冷启动从磁盘读也会是 dark。
    final fromDisk = await SettingsRepository.load();
    expect(fromDisk.theme, AppThemePreference.dark);
  });
}
