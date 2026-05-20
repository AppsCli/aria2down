import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../aria2/client/aria2_exceptions.dart'
    show Aria2BinaryNotFoundException, Aria2WebLocalUnsupportedException;
import '../core/platform_hints.dart';
import '../core/rpc_error_message.dart';
import '../data/app_settings.dart';
import '../data/settings_repository.dart';
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
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final showRemoteHint =
        (kIsWeb || isMobilePlatform) &&
        settings?.connectionMode != ConnectionMode.remote;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.daemonErrorTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SelectableText(_message(l10n)),
            if (showRemoteHint) ...[
              const SizedBox(height: 16),
              Text(
                l10n.platformHintMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                ref.invalidate(aria2DaemonProvider);
              },
              icon: const Icon(Icons.refresh),
              label: Text(l10n.daemonErrorRetry),
            ),
            if (showRemoteHint) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final current = await ref.read(appSettingsProvider.future);
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings_outlined),
              label: Text(l10n.platformHintOpenSettings),
            ),
          ],
        ),
      ),
    );
  }
}
