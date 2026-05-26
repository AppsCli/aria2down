import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../aria2/client/aria2_exceptions.dart'
    show Aria2BinaryNotFoundException, Aria2WebLocalUnsupportedException;
import '../core/platform_hints.dart';
import '../core/rpc_error_message.dart';
import '../data/app_settings.dart';
import '../data/settings_repository.dart';
import '../features/settings/settings_page.dart';
import '../providers/app_settings_provider.dart';
import '../providers/aria2_daemon_provider.dart';

class DaemonErrorScreen extends ConsumerWidget {
  const DaemonErrorScreen({super.key, required this.error});

  final Object error;

  String _message(AppLocalizations l10n) {
    if (error is Aria2BinaryNotFoundException) {
      return l10n.daemonErrorBinaryNotFound;
    }
    if (error is Aria2WebLocalUnsupportedException) {
      return l10n.daemonErrorWebLocal;
    }
    if (error is UnsupportedError) {
      return l10n.daemonErrorWebLocal;
    }
    return formatRpcError(l10n, error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final showRemoteHint =
        (kIsWeb || isMobilePlatform) &&
        settings?.connectionMode != ConnectionMode.remote;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 40,
                    color: scheme.error,
                  ),
                ).align(Alignment.center),
                const SizedBox(height: 20),
                Text(
                  l10n.daemonErrorTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _message(l10n),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
                if (showRemoteHint) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      l10n.platformHintMessage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(aria2DaemonProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.daemonErrorRetry),
                ),
                if (showRemoteHint) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final current = await ref.read(
                        appSettingsProvider.future,
                      );
                      await SettingsRepository.save(
                        current.copyWith(connectionMode: ConnectionMode.remote),
                      );
                      ref.invalidate(appSettingsProvider);
                      ref.invalidate(aria2DaemonProvider);
                    },
                    icon: const Icon(Icons.cloud_outlined),
                    label: Text(l10n.daemonErrorSwitchRemote),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  // 此页面通常在 daemon 启动失败时直接挂在 MaterialApp.home 之下，
                  // 此时还没有 GoRouter 上下文，必须用 Navigator.push 而非 context.go。
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  ),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(l10n.platformHintOpenSettings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on Widget {
  Widget align(Alignment a) => Align(alignment: a, child: this);
}
