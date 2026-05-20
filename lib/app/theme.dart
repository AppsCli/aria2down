import 'package:flutter/material.dart';

import '../core/platform_hints.dart';

ThemeData buildAria2downTheme(Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: brightness,
    ),
    visualDensity: isMobilePlatform
        ? VisualDensity.compact
        : VisualDensity.standard,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
      backgroundColor: base.colorScheme.surfaceContainerLow,
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: isMobilePlatform ? 8 : null,
    ),
  );
}
