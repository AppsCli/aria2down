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
    return AppSettings(
      connectionMode: _enum(
        m['connectionMode'],
        ConnectionMode.values,
        ConnectionMode.local,
      ),
      localEngine: _enum(
        m['localEngine'],
        LocalEngine.values,
        LocalEngine.library,
      ),
      fallbackToSubprocess: m['fallbackToSubprocess'] as bool? ?? true,
      remoteRpcEndpoint: m['remoteRpcEndpoint'] as String?,
      remoteRpcSecret: m['remoteRpcSecret'] as String?,
      aria2BinaryPath: m['aria2BinaryPath'] as String?,
      downloadDirectoryOverride: m['downloadDirectoryOverride'] as String?,
      theme: _enum(
        m['theme'],
        AppThemePreference.values,
        AppThemePreference.system,
      ),
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
    'localEngine': s.localEngine.name,
    'fallbackToSubprocess': s.fallbackToSubprocess,
    'remoteRpcEndpoint': s.remoteRpcEndpoint,
    'remoteRpcSecret': s.remoteRpcSecret,
    'aria2BinaryPath': s.aria2BinaryPath,
    'downloadDirectoryOverride': s.downloadDirectoryOverride,
    'theme': s.theme.name,
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

  /// 从 [SettingsRepository] 持久化键还原（与 SharedPreferences 键一致）。
  static AppSettings fromPreferenceMap(Map<String, Object?> prefs) {
    return AppSettings(
      connectionMode: SettingsRepository.readConnectionMode(
        prefs[SettingsKeys.connectionMode] as String?,
      ),
      localEngine: SettingsRepository.readLocalEngine(
        prefs[SettingsKeys.localEngine] as String?,
      ),
      fallbackToSubprocess:
          prefs[SettingsKeys.fallbackToSubprocess] as bool? ?? true,
      remoteRpcEndpoint: prefs[SettingsKeys.remoteRpcEndpoint] as String?,
      remoteRpcSecret: prefs[SettingsKeys.remoteRpcSecret] as String?,
      aria2BinaryPath: prefs[SettingsKeys.aria2BinaryPath] as String?,
      downloadDirectoryOverride: prefs[SettingsKeys.downloadDir] as String?,
      theme: SettingsRepository.readTheme(prefs[SettingsKeys.theme] as String?),
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
