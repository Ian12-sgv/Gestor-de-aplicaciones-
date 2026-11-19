import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/apps/presentation/app_detail_screen.dart';
import '../features/apps/presentation/apps_list_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/apps',
    routes: <RouteBase>[
      GoRoute(
        path: '/apps',
        builder: (context, state) => const AppsListScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final appId = state.pathParameters['id']!;
              return AppDetailScreen(appId: appId);
            },
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);

  return router;
});
