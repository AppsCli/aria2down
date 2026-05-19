import 'package:go_router/go_router.dart';

import '../core/add_task_prefill.dart';
import '../features/add/add_task_page.dart';
import '../features/settings/settings_page.dart';
import '../features/tasks/task_detail_page.dart';
import '../features/tasks/task_list_page.dart';
import 'main_shell.dart';

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: '/tasks',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => const TaskListPage(),
                routes: [
                  GoRoute(
                    path: 'detail/:gid',
                    builder: (context, state) =>
                        TaskDetailPage(gid: state.pathParameters['gid']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/add',
                builder: (context, state) => AddTaskPage(
                  initialUris: parsePrefillUrisFromQuery(state.uri),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
