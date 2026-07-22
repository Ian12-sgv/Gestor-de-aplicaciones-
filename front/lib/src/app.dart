import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/apps/data/app_runtime_service.dart';
import 'features/apps/presentation/apps_controller.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

class CorporateApp extends ConsumerStatefulWidget {
  const CorporateApp({super.key});

  @override
  ConsumerState<CorporateApp> createState() => _CorporateAppState();
}

class _CorporateAppState extends ConsumerState<CorporateApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: _handleResume,
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'pdb Store',
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }

  void _handleResume() {
    final session = ref.read(authControllerProvider).valueOrNull;

    if (session == null) {
      return;
    }

    ref.read(appsControllerProvider.notifier).refreshCatalog();
    ref.invalidate(installEnvironmentInfoProvider);
  }
}
