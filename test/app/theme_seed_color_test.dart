// 验证 [buildAria2downTheme] 的种子色参数确实驱动 Material 3 调色板。
//
// 主题色设置功能依赖：
// 1. 用户在设置里换 seed → MaterialApp 重建 theme → 整个应用 primary 色变化。
// 2. 不传 seed（默认）→ 与 [kDefaultSeedColor] 等价（品牌色不会被无意修改）。
//
// 这两条断言失败时，意味着「我换了主题色但界面没变」或「升级后默认色被
// 偷偷换掉了」之一会复现到用户。

import 'package:aria2down/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未指定 seedColor 时与品牌默认色 kDefaultSeedColor 等价', () {
    final defaulted = buildAria2downTheme(Brightness.light);
    final explicit = buildAria2downTheme(
      Brightness.light,
      seedColor: kDefaultSeedColor,
    );
    expect(defaulted.colorScheme.primary, explicit.colorScheme.primary);
    expect(defaulted.colorScheme.tertiary, explicit.colorScheme.tertiary);
  });

  test('不同 seedColor 推导出不同的 primary（设置真的会影响主题）', () {
    final blue = buildAria2downTheme(
      Brightness.light,
      seedColor: const Color(0xFF1565C0),
    );
    final purple = buildAria2downTheme(
      Brightness.light,
      seedColor: const Color(0xFF7E57C2),
    );
    expect(
      blue.colorScheme.primary,
      isNot(equals(purple.colorScheme.primary)),
      reason: '不同种子色必须落在 Material 3 不同 tonal palette 上',
    );
  });

  test('同 seedColor 在 light/dark 下都生效，但 primary 各自适配亮度', () {
    const seed = Color(0xFF2E7D32);
    final light = buildAria2downTheme(Brightness.light, seedColor: seed);
    final dark = buildAria2downTheme(Brightness.dark, seedColor: seed);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    // 同一种子色下，light/dark primary 必须落在不同 tonal level；否则用户
    // 在 dark 模式看不见对比度。
    expect(light.colorScheme.primary, isNot(equals(dark.colorScheme.primary)));
  });
}
