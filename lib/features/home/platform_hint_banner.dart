import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform_hints.dart';
import '../../data/app_settings.dart';
import '../../data/onboarding_repository.dart';
import '../../providers/app_settings_provider.dart';

/// 在移动/Web 平台提示使用远程 RPC（可关闭）。
class PlatformHintBanner extends ConsumerStatefulWidget {
  const PlatformHintBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlatformHintBanner> createState() => _PlatformHintBannerState();
}

class _PlatformHintBannerState extends ConsumerState<PlatformHintBanner> {
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!shouldPreferRemoteAria2) return;
    final dismissed = await OnboardingRepository.isPlatformHintDismissed();
    if (!mounted) return;
    setState(() => _visible = !dismissed);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    if (!_visible ||
        settings == null ||
        settings.connectionMode == ConnectionMode.remote) {
      return widget.child;
    }

    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MaterialBanner(
          content: Text(l10n.platformHintMessage),
          leading: const Icon(Icons.cloud_outlined),
          actions: [
            TextButton(
              onPressed: () => context.go('/settings'),
              child: Text(l10n.platformHintOpenSettings),
            ),
            TextButton(
              onPressed: () async {
                await OnboardingRepository.dismissPlatformHint();
                if (mounted) setState(() => _visible = false);
              },
              child: Text(l10n.platformHintDismiss),
            ),
          ],
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
