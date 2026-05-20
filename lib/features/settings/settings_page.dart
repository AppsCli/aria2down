import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../aria2/daemon/local_daemon_paths.dart';
import '../../core/launch_at_startup_helper.dart';
import '../../core/platform_hints.dart';
import '../../core/rpc_error_message.dart';
import '../../core/app_deep_link.dart';
import '../../core/local_rpc_credentials.dart';
import '../../core/remote_rpc_probe.dart';
import '../../data/app_settings.dart';
import '../../data/settings_export.dart';
import '../../data/settings_repository.dart';
import '../../desktop/desktop_shell.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/aria2_daemon_provider.dart';
import '../../providers/connection_info_provider.dart'
    show ActiveEngine, ConnectionInfo, connectionInfoProvider;
import '../about/about_page.dart';
import 'aria2_global_options_page.dart';
import 'aria2_log_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(appSettingsProvider)
        .when(
          data: (s) => _SettingsForm(key: ValueKey(s), initial: s, ref: ref),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
        );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({super.key, required this.initial, required this.ref});

  final AppSettings initial;
  final WidgetRef ref;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

String _engineLabel(AppLocalizations l10n, ConnectionInfo c) {
  final modeLabel = c.mode == ConnectionMode.local
      ? l10n.connectionLocal
      : l10n.connectionRemote;
  final engineLabel = switch (c.engine) {
    ActiveEngine.library => l10n.engineLibraryShort,
    ActiveEngine.subprocess => l10n.engineSubprocessShort,
    ActiveEngine.remote => l10n.engineRemoteShort,
  };
  return '$modeLabel · ${l10n.engineCurrent(engineLabel)}';
}

class _ConnectionStatusCard extends ConsumerWidget {
  const _ConnectionStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final info = ref.watch(connectionInfoProvider);
    return info.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.connectionStatusLoading,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.connectionStatusOffline,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      data: (c) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          child: ListTile(
            leading: Icon(c.wsAvailable ? Icons.link : Icons.link_off),
            title: Text(l10n.connectionStatusTitle),
            subtitle: Text(
              '${_engineLabel(l10n, c)}\n'
              '${c.httpEndpoint}\n'
              '${l10n.connectionStatusWs(c.wsAvailable ? l10n.taskDetailBoolYes : l10n.taskDetailBoolNo)}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: l10n.copyRpcEndpoint,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: c.httpEndpoint));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsFormState extends State<_SettingsForm> {
  late final TextEditingController _aria2PathCtrl;
  late final TextEditingController _remoteEndpointCtrl;
  late final TextEditingController _remoteSecretCtrl;
  late final TextEditingController _maxConcurrentCtrl;
  late final TextEditingController _maxConnCtrl;
  late final TextEditingController _dlLimitCtrl;
  late final TextEditingController _ulLimitCtrl;

  late ConnectionMode _connectionMode;
  late LocalEngine _localEngine;
  late bool _fallbackToSubprocess;
  late AppThemePreference _theme;
  late AppLocalePreference _locale;
  late bool _closeToTray;
  late bool _minimizeToTray;
  late bool _launchAtStartup;
  String? _downloadDir;
  bool _testingRemote = false;

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _connectionMode = kIsWeb ? ConnectionMode.remote : s.connectionMode;
    _localEngine = supportsSubprocessLocalEngine
        ? s.localEngine
        : LocalEngine.library;
    _fallbackToSubprocess = s.fallbackToSubprocess;
    _aria2PathCtrl = TextEditingController(text: s.aria2BinaryPath ?? '');
    _remoteEndpointCtrl = TextEditingController(
      text: s.remoteRpcEndpoint ?? '127.0.0.1:6800',
    );
    _remoteSecretCtrl = TextEditingController(text: s.remoteRpcSecret ?? '');
    _maxConcurrentCtrl = TextEditingController(
      text: s.maxConcurrentDownloads?.toString() ?? '',
    );
    _maxConnCtrl = TextEditingController(
      text: s.maxConnectionPerServer?.toString() ?? '',
    );
    _dlLimitCtrl = TextEditingController(text: s.globalDownloadLimit ?? '');
    _ulLimitCtrl = TextEditingController(text: s.globalUploadLimit ?? '');
    _theme = s.theme;
    _locale = s.locale;
    _closeToTray = s.closeToTray;
    _minimizeToTray = s.minimizeToTray;
    _launchAtStartup = s.launchAtStartup;
    _downloadDir = s.downloadDirectoryOverride;
  }

  @override
  void dispose() {
    _aria2PathCtrl.dispose();
    _remoteEndpointCtrl.dispose();
    _remoteSecretCtrl.dispose();
    _maxConcurrentCtrl.dispose();
    _maxConnCtrl.dispose();
    _dlLimitCtrl.dispose();
    _ulLimitCtrl.dispose();
    super.dispose();
  }

  AppSettings _buildSettings() {
    int? parsePositiveInt(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      final n = int.tryParse(t);
      if (n == null || n < 1) return null;
      return n;
    }

    return AppSettings(
      connectionMode: kIsWeb ? ConnectionMode.remote : _connectionMode,
      localEngine: supportsSubprocessLocalEngine
          ? _localEngine
          : LocalEngine.library,
      fallbackToSubprocess: _fallbackToSubprocess,
      remoteRpcEndpoint: _connectionMode == ConnectionMode.remote
          ? _remoteEndpointCtrl.text.trim()
          : null,
      remoteRpcSecret: _connectionMode == ConnectionMode.remote
          ? _remoteSecretCtrl.text.trim()
          : null,
      aria2BinaryPath: _aria2PathCtrl.text.trim().isEmpty
          ? null
          : _aria2PathCtrl.text.trim(),
      downloadDirectoryOverride: _downloadDir,
      theme: _theme,
      locale: _locale,
      closeToTray: _closeToTray,
      minimizeToTray: _minimizeToTray,
      launchAtStartup: _launchAtStartup,
      maxConcurrentDownloads: parsePositiveInt(_maxConcurrentCtrl.text),
      maxConnectionPerServer: parsePositiveInt(_maxConnCtrl.text),
      globalDownloadLimit: _dlLimitCtrl.text.trim().isEmpty
          ? null
          : _dlLimitCtrl.text.trim(),
      globalUploadLimit: _ulLimitCtrl.text.trim().isEmpty
          ? null
          : _ulLimitCtrl.text.trim(),
    );
  }

  Future<void> _pickDir(AppLocalizations l10n) async {
    try {
      final path = await getDirectoryPath(
        confirmButtonText: l10n.downloadDirectoryPick,
      );
      if (path != null && mounted) {
        setState(() => _downloadDir = path);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.folderPickerUnavailable)));
      }
    }
  }

  Future<void> _testRemoteConnection(AppLocalizations l10n) async {
    setState(() => _testingRemote = true);
    final result = await probeRemoteRpc(
      endpointRaw: _remoteEndpointCtrl.text.trim(),
      secret: _remoteSecretCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _testingRemote = false);
    final message = result.ok
        ? l10n.remoteTestOk(
            result.version ?? '?',
            result.wsReachable == true
                ? l10n.taskDetailBoolYes
                : l10n.taskDetailBoolNo,
          )
        : l10n.remoteTestFailed(
            formatRpcError(l10n, Exception(result.error ?? '')),
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyDeepLinkExample(AppLocalizations l10n) async {
    const example = 'https://example.com/file.zip';
    await Clipboard.setData(ClipboardData(text: buildInAppAddPath(example)));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.copyDeepLinkExampleDone)));
    }
  }

  Future<void> _copyExtensionRpcConfig(AppLocalizations l10n) async {
    final creds = await readLocalRpcCredentials();
    if (!mounted) return;
    if (creds == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.copyRpcConfigUnavailable)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: creds.extensionConfigJson));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.copyRpcConfigDone)));
    }
  }

  Future<void> _openAria2Log(AppLocalizations l10n) async {
    try {
      final path = await LocalDaemonPaths.logFilePath();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => Aria2LogPage(logPath: path)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _confirmShutdownAria2(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.shutdownAria2Title),
        content: Text(l10n.shutdownAria2Message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.shutdownAria2Confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final d = widget.ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.shutdown(force: false);
      widget.ref.invalidate(aria2DaemonProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.shutdownAria2Done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _confirmResetSettings(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.resetSettingsTitle),
        content: Text(l10n.resetSettingsMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.resetSettingsConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await SettingsRepository.resetToDefaults();
    widget.ref.invalidate(appSettingsProvider);
    widget.ref.invalidate(aria2DaemonProvider);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.resetSettingsDone)));
    }
  }

  Future<void> _applyRuntimeLimits(AppLocalizations l10n) async {
    final d = widget.ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final opts = <String, String>{};
    final dl = _dlLimitCtrl.text.trim();
    final ul = _ulLimitCtrl.text.trim();
    if (dl.isNotEmpty) opts['max-overall-download-limit'] = dl;
    if (ul.isNotEmpty) opts['max-overall-upload-limit'] = ul;
    final mc = int.tryParse(_maxConcurrentCtrl.text.trim());
    if (mc != null && mc > 0) {
      opts['max-concurrent-downloads'] = '$mc';
    }
    final conn = int.tryParse(_maxConnCtrl.text.trim());
    if (conn != null && conn > 0) {
      opts['max-connection-per-server'] = '$conn';
    }
    if (opts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.applyRuntimeLimitsEmpty)));
      }
      return;
    }
    try {
      await d.client.changeGlobalOption(opts);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.applyRuntimeLimitsDone)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _save(AppLocalizations l10n) async {
    final next = _buildSettings();
    await SettingsRepository.save(next);
    applyDesktopShellBehavior(next);
    await applyLaunchAtStartup(next);
    final d = widget.ref.read(aria2DaemonProvider).value;
    final dir = next.downloadDirectoryOverride?.trim();
    if (d != null && dir != null && dir.isNotEmpty) {
      try {
        await d.client.changeGlobalOption({'dir': dir});
      } catch (_) {
        /* 下次启动仍会从 aria2.conf 读取 */
      }
    }
    widget.ref.invalidate(appSettingsProvider);
    widget.ref.invalidate(aria2DaemonProvider);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.snackSaved)));
    }
  }

  Future<void> _exportSettings(AppLocalizations l10n) async {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(SettingsExport.toJson(_buildSettings()));
    if (_isDesktop) {
      try {
        final name =
            'aria2down-settings-${DateTime.now().toIso8601String().split('T').first}.json';
        final path = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );
        if (path != null) {
          final file = File(path.path);
          await file.writeAsString(json);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsExportSaved(path.path))),
            );
          }
          return;
        }
      } catch (_) {}
    }
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsExportCopied)));
    }
  }

  Future<void> _importSettings(AppLocalizations l10n) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      final path = result.files.single.path;
      final text = bytes != null
          ? utf8.decode(bytes)
          : (path != null ? await File(path).readAsString() : null);
      if (text == null || text.trim().isEmpty) return;

      final map = jsonDecode(text) as Map<String, dynamic>;
      final imported = SettingsExport.fromJson(map);
      if (!mounted) return;
      setState(() {
        _connectionMode = imported.connectionMode;
        _localEngine = imported.localEngine;
        _fallbackToSubprocess = imported.fallbackToSubprocess;
        _remoteEndpointCtrl.text =
            imported.remoteRpcEndpoint ?? '127.0.0.1:6800';
        _remoteSecretCtrl.text = imported.remoteRpcSecret ?? '';
        _aria2PathCtrl.text = imported.aria2BinaryPath ?? '';
        _downloadDir = imported.downloadDirectoryOverride;
        _theme = imported.theme;
        _locale = imported.locale;
        _closeToTray = imported.closeToTray;
        _minimizeToTray = imported.minimizeToTray;
        _launchAtStartup = imported.launchAtStartup;
        _maxConcurrentCtrl.text =
            imported.maxConcurrentDownloads?.toString() ?? '';
        _maxConnCtrl.text = imported.maxConnectionPerServer?.toString() ?? '';
        _dlLimitCtrl.text = imported.globalDownloadLimit ?? '';
        _ulLimitCtrl.text = imported.globalUploadLimit ?? '';
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsImportApplied)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.settingsImportFailed(formatRpcError(l10n, e))),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = Theme.of(context);

    final mobile = isMobilePlatform;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, mobile ? 96 : 16),
        children: [
          if (mobile)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.smartphone_outlined,
                      color: t.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.mobileSettingsCardTitle,
                            style: t.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.mobileSettingsCardBody,
                            style: t.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (mobile) const SizedBox(height: 16),
          Text(l10n.settingsConnection, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (kIsWeb)
            Text(l10n.settingsWebRemoteOnly, style: t.textTheme.bodySmall)
          else
            SegmentedButton<ConnectionMode>(
              segments: [
                ButtonSegment(
                  value: ConnectionMode.local,
                  label: Text(l10n.connectionLocal),
                ),
                ButtonSegment(
                  value: ConnectionMode.remote,
                  label: Text(l10n.connectionRemote),
                ),
              ],
              selected: {_connectionMode},
              onSelectionChanged: (v) =>
                  setState(() => _connectionMode = v.first),
            ),
          const _ConnectionStatusCard(),
          if (_connectionMode == ConnectionMode.local && !kIsWeb) ...[
            const SizedBox(height: 16),
            Text(l10n.settingsEngine, style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (supportsSubprocessLocalEngine)
              SegmentedButton<LocalEngine>(
                segments: [
                  ButtonSegment(
                    value: LocalEngine.library,
                    label: Text(l10n.engineLibrary),
                    icon: const Icon(Icons.memory_outlined),
                  ),
                  ButtonSegment(
                    value: LocalEngine.subprocess,
                    label: Text(l10n.engineSubprocess),
                    icon: const Icon(Icons.terminal_outlined),
                  ),
                ],
                selected: {_localEngine},
                onSelectionChanged: (v) =>
                    setState(() => _localEngine = v.first),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.memory_outlined),
                title: Text(l10n.engineLibrary),
                subtitle: Text(l10n.engineLibraryDesc),
              ),
            const SizedBox(height: 8),
            Text(
              _localEngine == LocalEngine.library
                  ? l10n.engineLibraryDesc
                  : l10n.engineSubprocessDesc,
              style: t.textTheme.bodySmall,
            ),
            if (_localEngine == LocalEngine.library &&
                supportsSubprocessLocalEngine) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.engineFallbackToSubprocess),
                subtitle: Text(l10n.engineFallbackToSubprocessDesc),
                value: _fallbackToSubprocess,
                onChanged: (v) => setState(() => _fallbackToSubprocess = v),
              ),
            ],
          ],
          if (_connectionMode == ConnectionMode.remote) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _remoteEndpointCtrl,
              decoration: InputDecoration(
                labelText: l10n.remoteRpcEndpoint,
                hintText: l10n.remoteRpcEndpointHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final preset
                    in mobile
                        ? const ['127.0.0.1:6800', '192.168.1.1:6800']
                        : const [
                            '127.0.0.1:6800',
                            'localhost:6800',
                            '0.0.0.0:6800',
                          ])
                  ActionChip(
                    label: Text(preset),
                    onPressed: () =>
                        setState(() => _remoteEndpointCtrl.text = preset),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remoteSecretCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.remoteRpcSecret,
                border: const OutlineInputBorder(),
              ),
            ),
            Text(l10n.remoteModeHint, style: t.textTheme.bodySmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testingRemote
                  ? null
                  : () => _testRemoteConnection(l10n),
              icon: _testingRemote
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(l10n.remoteTestConnection),
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.appearance, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(l10n.theme, style: t.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<AppThemePreference>(
            segments: [
              ButtonSegment(
                value: AppThemePreference.system,
                label: Text(l10n.themeSystem),
              ),
              ButtonSegment(
                value: AppThemePreference.light,
                label: Text(l10n.themeLight),
              ),
              ButtonSegment(
                value: AppThemePreference.dark,
                label: Text(l10n.themeDark),
              ),
            ],
            selected: {_theme},
            onSelectionChanged: (v) => setState(() => _theme = v.first),
          ),
          const SizedBox(height: 24),
          Text(l10n.language, style: t.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<AppLocalePreference>(
            segments: [
              ButtonSegment(
                value: AppLocalePreference.system,
                label: Text(l10n.langSystem),
              ),
              ButtonSegment(
                value: AppLocalePreference.en,
                label: Text(l10n.langEnglish),
              ),
              ButtonSegment(
                value: AppLocalePreference.zh,
                label: Text(l10n.langChinese),
              ),
            ],
            selected: {_locale},
            onSelectionChanged: (v) => setState(() => _locale = v.first),
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsDownloadTuning, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _maxConcurrentCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.maxConcurrentDownloads,
              hintText: l10n.settingsOptionalHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _maxConnCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.maxConnectionPerServer,
              hintText: '16',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _dlLimitCtrl,
            decoration: InputDecoration(
              labelText: l10n.globalDownloadLimit,
              hintText: l10n.speedLimitHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ulLimitCtrl,
            decoration: InputDecoration(
              labelText: l10n.globalUploadLimit,
              hintText: l10n.speedLimitHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_connectionMode == ConnectionMode.local)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.settingsTuningLocalOnly,
                style: t.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _applyRuntimeLimits(l10n),
            icon: const Icon(Icons.speed_outlined),
            label: Text(l10n.applyRuntimeLimits),
          ),
          Text(l10n.applyRuntimeLimitsHint, style: t.textTheme.bodySmall),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.downloadDirectory),
            subtitle: Text(
              _downloadDir ?? '(${l10n.downloadDirectoryClear})',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _pickDir(l10n),
                  child: Text(l10n.downloadDirectoryPick),
                ),
                TextButton(
                  onPressed: () => setState(() => _downloadDir = null),
                  child: Text(l10n.downloadDirectoryClear),
                ),
              ],
            ),
          ),
          if (_connectionMode == ConnectionMode.local &&
              _localEngine == LocalEngine.subprocess) ...[
            const SizedBox(height: 16),
            Text(l10n.aria2BinaryPath, style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _aria2PathCtrl,
              decoration: InputDecoration(
                hintText: l10n.aria2BinaryHint,
                border: const OutlineInputBorder(),
              ),
            ),
            Text(l10n.restartAria2Hint, style: t.textTheme.bodySmall),
          ],
          if (_isDesktop) ...[
            const SizedBox(height: 24),
            Text(l10n.settingsDesktop, style: t.textTheme.titleSmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.closeToTray),
              subtitle: Text(l10n.closeToTrayDesc),
              value: _closeToTray,
              onChanged: (v) => setState(() => _closeToTray = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.minimizeToTray),
              subtitle: Text(l10n.minimizeToTrayDesc),
              value: _minimizeToTray,
              onChanged: (v) => setState(() => _minimizeToTray = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.launchAtStartup),
              subtitle: Text(l10n.launchAtStartupDesc),
              value: _launchAtStartup,
              onChanged: (v) => setState(() => _launchAtStartup = v),
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.settingsBackup, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportSettings(l10n),
                icon: const Icon(Icons.upload_outlined),
                label: Text(l10n.settingsExport),
              ),
              OutlinedButton.icon(
                onPressed: () => _importSettings(l10n),
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.settingsImport),
              ),
            ],
          ),
          if (_connectionMode == ConnectionMode.local && !kIsWeb) ...[
            const SizedBox(height: 24),
            Text(l10n.settingsDiagnostics, style: t.textTheme.titleSmall),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: Text(l10n.aria2LogTitle),
              subtitle: Text(l10n.aria2LogSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openAria2Log(l10n),
            ),
            if (_localEngine == LocalEngine.subprocess)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.extension_outlined),
                title: Text(l10n.copyRpcConfigTitle),
                subtitle: Text(l10n.copyRpcConfigSubtitle),
                onTap: () => _copyExtensionRpcConfig(l10n),
              ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: Text(l10n.aria2GlobalOptionsTitle),
            subtitle: Text(l10n.aria2GlobalOptionsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Aria2GlobalOptionsPage(),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link_outlined),
            title: Text(l10n.copyDeepLinkExampleTitle),
            subtitle: Text(l10n.copyDeepLinkExampleSubtitle),
            onTap: () => _copyDeepLinkExample(l10n),
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsDangerZone, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmShutdownAria2(l10n),
            icon: const Icon(Icons.power_settings_new),
            label: Text(l10n.shutdownAria2),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _confirmResetSettings(l10n),
            child: Text(l10n.resetSettings),
          ),
          if (!mobile) ...[
            const SizedBox(height: 24),
            FilledButton(onPressed: () => _save(l10n), child: Text(l10n.save)),
          ],
          const SizedBox(height: 32),
          Text(l10n.about, style: t.textTheme.titleSmall),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutTitle),
            subtitle: Text(l10n.aboutOpenDetail),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ],
      ),
      bottomNavigationBar: mobile
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton(
                  onPressed: () => _save(l10n),
                  child: Text(l10n.save),
                ),
              ),
            )
          : null,
    );
  }
}
