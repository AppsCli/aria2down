import '../core/app_meta.dart';
import 'app_settings.dart';
import 'settings_repository.dart';

/// 设置导入/导出（JSON，便于备份与迁移）。
abstract final class SettingsExport {
  static const currentVersion = 1;

  static Map<String, dynamic> toJson(AppSettings s) => {
    'version': currentVersion,
    'appVersion': AppMeta.version,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'settings': _settingsMap(s),
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int || version > currentVersion) {
      throw FormatException('不支持的设置版本：$version');
    }
    final raw = json['settings'];
    if (raw is! Map) {
      throw const FormatException('缺少 settings 对象');
    }
    return _settingsFromMap(Map<String, dynamic>.from(raw));
  }

  static AppSettings _settingsFromMap(Map<String, dynamic> m) {
    // 历史字段 `localEngine` / `fallbackToSubprocess` / `aria2BinaryPath` 在
    // ADR-010 后已经移除。旧导出 JSON 里若还有这几条键，这里**静默忽略**——
    // 这样老用户从 v0.5.x 备份的 settings.json 也能直接导入，不会因为 enum
    // 解析失败让整个 fromJson 抛 FormatException。
    return AppSettings(
      connectionMode: _enum(
        m['connectionMode'],
        ConnectionMode.values,
        ConnectionMode.local,
      ),
      remoteRpcEndpoint: m['remoteRpcEndpoint'] as String?,
      remoteRpcSecret: m['remoteRpcSecret'] as String?,
      downloadDirectoryOverride: m['downloadDirectoryOverride'] as String?,
      askDownloadDirEachTime: m['askDownloadDirEachTime'] as bool? ?? false,
      theme: _enum(
        m['theme'],
        AppThemePreference.values,
        AppThemePreference.system,
      ),
      seedColorArgb: _intOrNull(m['seedColorArgb']),
      locale: _enum(
        m['locale'],
        AppLocalePreference.values,
        AppLocalePreference.system,
      ),
      closeToTray: m['closeToTray'] as bool? ?? true,
      minimizeToTray: m['minimizeToTray'] as bool? ?? false,
      launchAtStartup: m['launchAtStartup'] as bool? ?? false,
      startMinimized: m['startMinimized'] as bool? ?? false,
      keepAliveInBackground: m['keepAliveInBackground'] as bool? ?? true,
      maxConcurrentDownloads: m['maxConcurrentDownloads'] as int?,
      maxConnectionPerServer: m['maxConnectionPerServer'] as int?,
      globalDownloadLimit: m['globalDownloadLimit'] as String?,
      globalUploadLimit: m['globalUploadLimit'] as String?,
    );
  }

  static Map<String, dynamic> _settingsMap(AppSettings s) => {
    'connectionMode': s.connectionMode.name,
    'remoteRpcEndpoint': s.remoteRpcEndpoint,
    'remoteRpcSecret': s.remoteRpcSecret,
    'downloadDirectoryOverride': s.downloadDirectoryOverride,
    'askDownloadDirEachTime': s.askDownloadDirEachTime,
    'theme': s.theme.name,
    'seedColorArgb': s.seedColorArgb,
    'locale': s.locale.name,
    'closeToTray': s.closeToTray,
    'minimizeToTray': s.minimizeToTray,
    'launchAtStartup': s.launchAtStartup,
    'startMinimized': s.startMinimized,
    'keepAliveInBackground': s.keepAliveInBackground,
    'maxConcurrentDownloads': s.maxConcurrentDownloads,
    'maxConnectionPerServer': s.maxConnectionPerServer,
    'globalDownloadLimit': s.globalDownloadLimit,
    'globalUploadLimit': s.globalUploadLimit,
  };

  static T _enum<T extends Enum>(Object? raw, List<T> values, T fallback) {
    if (raw is! String || raw.isEmpty) return fallback;
    try {
      return values.byName(raw);
    } catch (_) {
      return fallback;
    }
  }

  /// 容忍 JSON 反序列化里出现的 `int`、`num`（带小数的 e.g. `4.28e9`）、
  /// `String`（手编 JSON）三种形态。无效输入退化到 null，让 [AppSettings]
  /// 回退到应用品牌默认色。
  static int? _intOrNull(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// 从 [SettingsRepository] 持久化键还原（与 SharedPreferences 键一致）。
  static AppSettings fromPreferenceMap(Map<String, Object?> prefs) {
    return AppSettings(
      connectionMode: SettingsRepository.readConnectionMode(
        prefs[SettingsKeys.connectionMode] as String?,
      ),
      remoteRpcEndpoint: prefs[SettingsKeys.remoteRpcEndpoint] as String?,
      remoteRpcSecret: prefs[SettingsKeys.remoteRpcSecret] as String?,
      downloadDirectoryOverride: prefs[SettingsKeys.downloadDir] as String?,
      askDownloadDirEachTime:
          prefs[SettingsKeys.askDownloadDir] as bool? ?? false,
      theme: SettingsRepository.readTheme(prefs[SettingsKeys.theme] as String?),
      seedColorArgb: prefs[SettingsKeys.seedColor] as int?,
      locale: SettingsRepository.readLocale(
        prefs[SettingsKeys.locale] as String?,
      ),
      closeToTray: prefs[SettingsKeys.closeToTray] as bool? ?? true,
      minimizeToTray: prefs[SettingsKeys.minimizeToTray] as bool? ?? false,
      launchAtStartup: prefs[SettingsKeys.launchAtStartup] as bool? ?? false,
      startMinimized: prefs[SettingsKeys.startMinimized] as bool? ?? false,
      keepAliveInBackground:
          prefs[SettingsKeys.keepAliveInBackground] as bool? ?? true,
      maxConcurrentDownloads: prefs[SettingsKeys.maxConcurrent] as int?,
      maxConnectionPerServer: prefs[SettingsKeys.maxConnPerServer] as int?,
      globalDownloadLimit: prefs[SettingsKeys.globalDownloadLimit] as String?,
      globalUploadLimit: prefs[SettingsKeys.globalUploadLimit] as String?,
    );
  }
}
