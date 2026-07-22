import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/apps/presentation/app_detail_screen.dart';
import '../features/apps/presentation/apps_list_screen.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  final isLoggedIn = authState.valueOrNull != null;
  final mustChangePassword =
      authState.valueOrNull?.user.passwordMustChange ?? false;

  return GoRouter(
    initialLocation: isLoggedIn
        ? (mustChangePassword ? '/change-password' : '/apps')
        : '/login',
    redirect: (context, state) {
      final currentAuth = ref.read(authControllerProvider);
      final currentSession = currentAuth.valueOrNull;
      final loggedIn = currentSession != null;
      final requiresPasswordChange =
          currentSession?.user.passwordMustChange ?? false;
      final isLoginRoute = state.matchedLocation == '/login';
      final isChangePasswordRoute = state.matchedLocation == '/change-password';

      if (!loggedIn && !isLoginRoute) {
        return '/login';
      }

      if (loggedIn && requiresPasswordChange && !isChangePasswordRoute) {
        return '/change-password';
      }

      if (loggedIn && !requiresPasswordChange && isChangePasswordRoute) {
        return '/apps';
      }

      if (loggedIn && isLoginRoute) {
        return requiresPasswordChange ? '/change-password' : '/apps';
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
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
});
