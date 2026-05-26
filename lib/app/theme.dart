import 'package:flutter/material.dart';

import '../core/platform_hints.dart';

/// 应用主题。
///
/// 设计原则：
/// - **Material 3 + seed color**：以品牌色 `#1565C0`（一个偏冷的「下载箭头蓝」）
///   作为 `ColorScheme.fromSeed` 种子；让 light / dark 自动调色，避免手工维护
///   两套色板。
/// - **圆角统一**：Card 16、Dialog 20、Button 12、Chip 8、Input 12——给应用一
///   层「现代化、克制」的视觉语言。
/// - **AppBar 平面化**：scrolledUnderElevation=0 + 用 `surfaceContainerLow` 背景
///   色，避免默认材质阴影在桌面端的视觉杂讯。
/// - **桌面 vs 移动密度**：移动端 [VisualDensity.compact] 让一屏放下更多任务；
///   桌面端保持 standard 避免按钮过小被误点。
ThemeData buildAria2downTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1565C0),
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: isMobilePlatform
        ? VisualDensity.compact
        : VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    // AppBar 平面化 + 与 surfaceContainerLow 融合。tasks/details/settings 共
    // 用同一感觉。
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    // Tab：去掉默认下划线的拉伸效果，加圆角的 indicator 与品牌色文字。
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.5),
      indicator: UnderlineTabIndicator(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        borderSide: BorderSide(width: 2.5, color: scheme.primary),
      ),
    ),
    // 卡片：圆角 16 + 极轻填色（surfaceContainerLow）+ 0 阴影；让 Card 在
    // ListView 里像一块块「材质卡片」，不再是浮起的 elevation 1 块。
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
    ),
    // Dialog：圆角 20，比 Card 略大一档，强调对话框的层级。
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    // 三大类按钮统一圆角 12 + 内边距。FilledButton 是首选行动；OutlinedButton
    // 用于次要；TextButton 用于辅助 / dialog cancel。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
    // SegmentedButton：本应用大量用于"本机/远程""库引擎/子进程"二选一切换；
    // 圆角 12 + selected 色调来自 primaryContainer 让对比清晰。
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        ),
      ),
    ),
    // FAB：在移动端是主入口，加 elevation 阴影更明显 + 圆角 18 让方形渐变到圆。
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    // 输入框：圆角 12 + 极轻底色（surfaceContainerHighest）让 TextField 看起来
    // 像「凹陷的填字面板」而非传统下划线表单。
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    // Chip：用于状态徽章 / 任务计数；rounded 8 + 不显示边框更轻盈。
    chipTheme: ChipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
      labelStyle: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    ),
    // Divider 颜色降到 outlineVariant.withAlpha(0.5)，避免在 Card 内部分割线
    // 太抢眼。
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 1,
    ),
    // ListTile 默认 padding & 圆角：让 swipe 背景在边缘也带圆角看起来更整体。
    listTileTheme: ListTileThemeData(
      minVerticalPadding: isMobilePlatform ? 8 : 12,
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    // 进度条：linear 用更细的 4 px + 圆角；用 primary 在 surfaceVariant 上
    // 显得鲜明。详情页 / tile 共用。
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 5,
      linearTrackColor: scheme.surfaceContainerHighest,
      color: scheme.primary,
    ),
    // SnackBar：圆角 12 + floating + inverseSurface 让提示从底部浮出。
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
    ),
    // 桌面侧栏：与 AppBar 同底色，去掉默认的 elevation 阴影。
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      ),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      indicatorColor: scheme.primaryContainer,
      useIndicator: true,
    ),
    // 移动底部导航条：与 surface 融合 + 加粗选中文字。
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        );
      }),
    ),
    // BottomSheet（context sheet / 路径分享 sheet）：底部圆角更大让弹层有「拉
    // 起卡片」的感觉。
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      modalBackgroundColor: scheme.surfaceContainerLow,
      dragHandleColor: scheme.outlineVariant,
      surfaceTintColor: Colors.transparent,
    ),
    // PopupMenu（任务列表批量菜单等）：圆角 12 + 与 Card 同底色。
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
    ),
    // Tooltip：更浅的底色，圆角 8。
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    // 深色模式下的细微调色：让 surfaceContainerLow 与 surface 拉开一档对比。
    extensions: [Aria2downColors._fromScheme(scheme, isDark: isDark)],
  );
}

/// 应用扩展色 token：放在 ThemeExtension 里供任务 tile 等组件读取一致的「状态
/// 色板」。集中定义比每处 `colorScheme.error` / 手工色值更稳定。
@immutable
class Aria2downColors extends ThemeExtension<Aria2downColors> {
  const Aria2downColors({
    required this.statusActive,
    required this.statusActiveSurface,
    required this.statusPaused,
    required this.statusPausedSurface,
    required this.statusComplete,
    required this.statusCompleteSurface,
    required this.statusError,
    required this.statusErrorSurface,
    required this.statusWaiting,
    required this.statusWaitingSurface,
    required this.downloadAccent,
    required this.uploadAccent,
  });

  /// active 任务：用 primary 系——下载中。
  final Color statusActive;
  final Color statusActiveSurface;

  /// paused：用 tertiary 系——暂停（暖色但不告警）。
  final Color statusPaused;
  final Color statusPausedSurface;

  /// complete：绿色——成功完成。
  final Color statusComplete;
  final Color statusCompleteSurface;

  /// error / removed：错误红。
  final Color statusError;
  final Color statusErrorSurface;

  /// waiting：中性蓝灰。
  final Color statusWaiting;
  final Color statusWaitingSurface;

  /// 速率显示：下载用 primary、上传用 tertiary，让两栏视觉上分明。
  final Color downloadAccent;
  final Color uploadAccent;

  factory Aria2downColors._fromScheme(
    ColorScheme scheme, {
    required bool isDark,
  }) {
    // 完成态用一组手挑绿——Material 3 默认 scheme 没有「绿」语义槽，借用
    // tertiaryContainer 容易和 paused 混淆。手挑保持品牌一致。
    const completeLight = Color(0xFF2E7D32);
    const completeDark = Color(0xFF81C995);
    const completeSurfaceLight = Color(0xFFE6F4EA);
    const completeSurfaceDark = Color(0x402E7D32);

    return Aria2downColors(
      statusActive: scheme.primary,
      statusActiveSurface: scheme.primaryContainer,
      statusPaused: scheme.tertiary,
      statusPausedSurface: scheme.tertiaryContainer,
      statusComplete: isDark ? completeDark : completeLight,
      statusCompleteSurface: isDark
          ? completeSurfaceDark
          : completeSurfaceLight,
      statusError: scheme.error,
      statusErrorSurface: scheme.errorContainer,
      statusWaiting: scheme.onSurfaceVariant,
      statusWaitingSurface: scheme.surfaceContainerHighest,
      downloadAccent: scheme.primary,
      uploadAccent: scheme.tertiary,
    );
  }

  @override
  Aria2downColors copyWith({
    Color? statusActive,
    Color? statusActiveSurface,
    Color? statusPaused,
    Color? statusPausedSurface,
    Color? statusComplete,
    Color? statusCompleteSurface,
    Color? statusError,
    Color? statusErrorSurface,
    Color? statusWaiting,
    Color? statusWaitingSurface,
    Color? downloadAccent,
    Color? uploadAccent,
  }) {
    return Aria2downColors(
      statusActive: statusActive ?? this.statusActive,
      statusActiveSurface: statusActiveSurface ?? this.statusActiveSurface,
      statusPaused: statusPaused ?? this.statusPaused,
      statusPausedSurface: statusPausedSurface ?? this.statusPausedSurface,
      statusComplete: statusComplete ?? this.statusComplete,
      statusCompleteSurface:
          statusCompleteSurface ?? this.statusCompleteSurface,
      statusError: statusError ?? this.statusError,
      statusErrorSurface: statusErrorSurface ?? this.statusErrorSurface,
      statusWaiting: statusWaiting ?? this.statusWaiting,
      statusWaitingSurface: statusWaitingSurface ?? this.statusWaitingSurface,
      downloadAccent: downloadAccent ?? this.downloadAccent,
      uploadAccent: uploadAccent ?? this.uploadAccent,
    );
  }

  @override
  Aria2downColors lerp(ThemeExtension<Aria2downColors>? other, double t) {
    if (other is! Aria2downColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return Aria2downColors(
      statusActive: l(statusActive, other.statusActive),
      statusActiveSurface: l(statusActiveSurface, other.statusActiveSurface),
      statusPaused: l(statusPaused, other.statusPaused),
      statusPausedSurface: l(statusPausedSurface, other.statusPausedSurface),
      statusComplete: l(statusComplete, other.statusComplete),
      statusCompleteSurface: l(
        statusCompleteSurface,
        other.statusCompleteSurface,
      ),
      statusError: l(statusError, other.statusError),
      statusErrorSurface: l(statusErrorSurface, other.statusErrorSurface),
      statusWaiting: l(statusWaiting, other.statusWaiting),
      statusWaitingSurface: l(statusWaitingSurface, other.statusWaitingSurface),
      downloadAccent: l(downloadAccent, other.downloadAccent),
      uploadAccent: l(uploadAccent, other.uploadAccent),
    );
  }

  /// 通过当前 [BuildContext] 读取扩展色；找不到时返回 [_fallback]。
  static Aria2downColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<Aria2downColors>() ??
        Aria2downColors._fromScheme(
          theme.colorScheme,
          isDark: theme.brightness == Brightness.dark,
        );
  }
}
