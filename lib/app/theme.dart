import 'package:flutter/material.dart';

ThemeData buildAria2downTheme(Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: brightness,
    ),
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
      backgroundColor: base.colorScheme.surfaceContainerLow,
    ),
  );
}
