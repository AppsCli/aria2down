import 'dart:io' show Platform;

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/desktop_shortcuts.dart';
import '../../core/app_meta.dart';
import '../../data/app_settings.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/aria2_daemon_provider.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  static const _aria2Url = 'https://github.com/aria2/aria2';
  static const _licenseUrl = 'https://www.gnu.org/licenses/gpl-2.0.html';

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final t = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final daemon = ref.watch(aria2DaemonProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.download_for_offline_outlined,
            size: 72,
            color: t.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.appTitle,
            style: t.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.appVersionLabel(AppMeta.version),
            style: t.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (daemon != null) ...[
            const SizedBox(height: 24),
            Text(l10n.aboutRpcInfo, style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            SelectableText(daemon.rpcHttpUri.toString()),
            if (settings?.connectionMode == ConnectionMode.local &&
                daemon.rpcSecret.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.aboutRpcSecretHint, style: t.textTheme.bodySmall),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      daemon.rpcSecret,
                      style: t.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.copyValue,
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: daemon.rpcSecret),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.snackCopied)),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ],
          if (DesktopShortcuts.enabled) ...[
            const SizedBox(height: 24),
            Text(l10n.aboutDesktopShortcuts, style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            _ShortcutRow(
              label: l10n.desktopShortcutRefresh,
              keys: Platform.isMacOS ? '⌘ R' : 'Ctrl+R',
            ),
            _ShortcutRow(
              label: l10n.desktopShortcutAdd,
              keys: Platform.isMacOS ? '⌘ N' : 'Ctrl+N',
            ),
            _ShortcutRow(
              label: l10n.desktopShortcutSettings,
              keys: Platform.isMacOS ? '⌘ ,' : 'Ctrl+,',
            ),
          ],
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension_outlined),
            title: Text(l10n.aboutBrowserExtension),
            subtitle: Text(l10n.aboutBrowserExtensionHint),
          ),
          const SizedBox(height: 24),
          Text(l10n.aboutDesc),
          const SizedBox(height: 16),
          Text(l10n.aboutPoweredBy, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: const Text('aria2'),
            subtitle: Text(_aria2Url),
            onTap: () => _open(Uri.parse(_aria2Url)),
          ),
          const SizedBox(height: 16),
          Text(l10n.aboutLicense, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(l10n.aboutLicenseBody),
          TextButton(
            onPressed: () => _open(Uri.parse(_licenseUrl)),
            child: Text(l10n.aboutLicenseLink),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            keys,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
