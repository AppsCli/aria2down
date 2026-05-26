// 13 个 [AppLocalePreference] 都必须能正确映射到 Flutter `Locale`，并能
// round-trip 通过 [SettingsRepository.readLocale] / [SettingsExport]。这两层
// 都是用 `enum.byName(rawString)` 的 String 路径解析：增加新 locale 时容易
// 漏改 switch 表，让 settings 改了但 UI 不切换语言。
//
// 这里逐条断言：每个 enum 值都有非 null 的 Locale（除 system）+ 与
// SettingsExport JSON round-trip 保持一致。

import 'package:aria2down/data/app_settings.dart';
import 'package:aria2down/data/settings_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLocalePreference.localeOrNull 全覆盖', () {
    test('system → null（沿用系统语言）', () {
      final s = const AppSettings(locale: AppLocalePreference.system);
      expect(s.localeOrNull, isNull);
    });

    test('en/zh 等 13 种 enum 值都映射到合法 Locale', () {
      // 期望 languageCode + countryCode（zhTw 是唯一带 countryCode 的）。
      final expected = <AppLocalePreference, (String, String?)>{
        AppLocalePreference.en: ('en', null),
        AppLocalePreference.zh: ('zh', null),
        AppLocalePreference.zhTw: ('zh', 'TW'),
        AppLocalePreference.ja: ('ja', null),
        AppLocalePreference.ko: ('ko', null),
        AppLocalePreference.es: ('es', null),
        AppLocalePreference.fr: ('fr', null),
        AppLocalePreference.de: ('de', null),
        AppLocalePreference.ru: ('ru', null),
        AppLocalePreference.pt: ('pt', null),
        AppLocalePreference.ar: ('ar', null),
        AppLocalePreference.vi: ('vi', null),
      };
      // 防御性：如果将来添加新枚举值忘记更新此表，直接报错。
      expect(
        expected.length,
        AppLocalePreference.values.length - 1, // 减去 system
        reason: '本测试需覆盖所有非 system 的 AppLocalePreference 值',
      );
      for (final entry in expected.entries) {
        final s = AppSettings(locale: entry.key);
        final loc = s.localeOrNull;
        expect(loc, isNotNull, reason: '${entry.key.name} 应映射到非 null Locale');
        expect(loc!.languageCode, entry.value.$1, reason: entry.key.name);
        expect(loc.countryCode, entry.value.$2, reason: entry.key.name);
      }
    });
  });

  group('SettingsExport round-trip 覆盖所有新增 locale', () {
    for (final p in AppLocalePreference.values) {
      test('${p.name} round-trip 保持稳定', () {
        final original = AppSettings(locale: p);
        final restored = SettingsExport.fromJson(
          SettingsExport.toJson(original),
        );
        expect(restored.locale, p);
      });
    }
  });
}
