import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform_hints.dart';
import '../../data/onboarding_repository.dart';

/// 首次进入主界面时，在移动/Web 上提示配置远程 RPC。
Future<void> maybeShowWelcomeRemoteDialog(BuildContext context) async {
  if (!shouldPreferRemoteAria2) return;
  if (!context.mounted) return;
  if (await OnboardingRepository.isWelcomeRemoteShown()) return;
  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.welcomeRemoteTitle),
      content: Text(l10n.welcomeRemoteBody),
      actions: [
        TextButton(
          onPressed: () async {
            await OnboardingRepository.setWelcomeRemoteShown();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(l10n.platformHintDismiss),
        ),
        FilledButton(
          onPressed: () async {
            await OnboardingRepository.setWelcomeRemoteShown();
            if (ctx.mounted) {
              Navigator.pop(ctx);
              ctx.go('/settings');
            }
          },
          child: Text(l10n.platformHintOpenSettings),
        ),
      ],
    ),
  );
}
