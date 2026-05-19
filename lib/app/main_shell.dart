import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/platform_hint_banner.dart';
import '../features/home/welcome_remote_dialog.dart';
import '../providers/task_badge_provider.dart';

/// 窄屏底栏 / 宽屏侧栏导航。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maybeShowWelcomeRemoteDialog(context);
    });
  }

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  Widget _tasksNavIcon(IconData icon) {
    final active = ref.watch(taskActiveCountProvider);
    return Badge(
      isLabelVisible: active > 0,
      label: Text('$active'),
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final l10n = AppLocalizations.of(context)!;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                extended: true,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _goBranch,
                destinations: [
                  NavigationRailDestination(
                    icon: _tasksNavIcon(Icons.download_outlined),
                    selectedIcon: _tasksNavIcon(Icons.download),
                    label: Text(l10n.navTasks),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.add_circle_outline),
                    selectedIcon: const Icon(Icons.add_circle),
                    label: Text(l10n.navAdd),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: Text(l10n.navSettings),
                  ),
                ],
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: PlatformHintBanner(child: navigationShell)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: PlatformHintBanner(child: navigationShell)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: [
          NavigationDestination(
            icon: _tasksNavIcon(Icons.download_outlined),
            selectedIcon: _tasksNavIcon(Icons.download),
            label: l10n.navTasks,
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline),
            selectedIcon: const Icon(Icons.add_circle),
            label: l10n.navAdd,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
