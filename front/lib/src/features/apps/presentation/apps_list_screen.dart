import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../device/domain/device_profile.dart';
import '../../device/presentation/device_controller.dart';
import '../data/android_app_bridge.dart';
import '../data/app_runtime_service.dart';
import '../domain/corporate_app.dart';
import 'apps_controller.dart';
import 'widgets/app_status_chip.dart';

class AppsListScreen extends ConsumerWidget {
  const AppsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final appsState = ref.watch(appsControllerProvider);
    final installEnvironmentAsync = ref.watch(installEnvironmentInfoProvider);
    final user = authState.valueOrNull?.user;
    final canRemoveFromDevice = user != null;
    final canDeleteFromStore = user?.canDeleteAppsFromStore ?? false;
    final currentUserLabel = user == null
        ? 'Usuario no identificado'
        : '${user.name} (${user.username})';

    return Scaffold(
      appBar: AppBar(
        title: const Text('pdb Store'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: () =>
                ref.read(appsControllerProvider.notifier).refreshCatalog(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _CurrentUserBanner(userLabel: currentUserLabel),
          ),
          Expanded(
            child: appsState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text('No se pudo cargar el catalogo: $error'),
              ),
              data: (apps) {
                final sortedApps = _sortApps(apps);
                final mandatoryApps = sortedApps
                    .where((app) => app.requiresImmediateUpdate)
                    .toList(growable: false);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    installEnvironmentAsync.when(
                      data: (installEnvironment) =>
                          installEnvironment.canInstallUnknownApps
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _InstallPermissionSetupCard(
                                    installEnvironment: installEnvironment,
                                  ),
                                ),
                      loading: () => const SizedBox.shrink(),
                      error: (error, stackTrace) => const SizedBox.shrink(),
                    ),
                    if (mandatoryApps.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _MandatoryUpdatesSummaryCard(
                          apps: mandatoryApps,
                        ),
                      ),
                    ...sortedApps.map(
                      (app) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AppListCard(
                          app: app,
                          canRemoveFromDevice: canRemoveFromDevice,
                          canDeleteFromStore: canDeleteFromStore,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static List<CorporateApp> _sortApps(List<CorporateApp> apps) {
    final sortedApps = List<CorporateApp>.of(apps);

    sortedApps.sort((left, right) {
      final priorityCompare = _priorityFor(right).compareTo(_priorityFor(left));
      if (priorityCompare != 0) {
        return priorityCompare;
      }

      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });

    return sortedApps;
  }

  static int _priorityFor(CorporateApp app) {
    if (app.requiresImmediateUpdate) {
      return 3;
    }

    if (app.primaryAction == AppPrimaryAction.update) {
      return 2;
    }

    if (app.primaryAction == AppPrimaryAction.install) {
      return 1;
    }

    return 0;
  }
}

class _CurrentUserBanner extends StatelessWidget {
  const _CurrentUserBanner({
    required this.userLabel,
  });

  final String userLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.account_circle_outlined, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sesion: $userLabel',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallPermissionSetupCard extends ConsumerStatefulWidget {
  const _InstallPermissionSetupCard({
    required this.installEnvironment,
  });

  final InstallEnvironmentInfo installEnvironment;

  @override
  ConsumerState<_InstallPermissionSetupCard> createState() =>
      _InstallPermissionSetupCardState();
}

class _InstallPermissionSetupCardState
    extends ConsumerState<_InstallPermissionSetupCard> {
  bool _isOpeningSettings = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canOpenSettings = widget.installEnvironment.settingsAvailable;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: colorScheme.secondary.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Prepara las instalaciones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Activa una vez el permiso de la Store para instalar apps corporativas. Asi evitaras este paso en cada descarga.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed:
                  canOpenSettings && !_isOpeningSettings ? _openSettings : null,
              icon: _isOpeningSettings
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.settings_outlined),
              label: const Text('Preparar instalaciones'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    setState(() {
      _isOpeningSettings = true;
    });

    final opened = await ref
        .read(androidAppBridgeProvider)
        .openInstallPermissionSettings();

    if (!mounted) {
      return;
    }

    setState(() {
      _isOpeningSettings = false;
    });

    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el permiso de instalacion.'),
        ),
      );
    }
  }
}

class _MandatoryUpdatesSummaryCard extends StatelessWidget {
  const _MandatoryUpdatesSummaryCard({
    required this.apps,
  });

  final List<CorporateApp> apps;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstApp = apps.first;
    final remainingApps = apps.length - 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    apps.length == 1
                        ? 'Hay 1 app con actualizacion obligatoria'
                        : 'Hay ${apps.length} apps con actualizacion obligatoria',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              remainingApps > 0
                  ? 'Empieza por ${firstApp.name}. Despues podras revisar las otras $remainingApps pendientes.'
                  : 'Empieza por ${firstApp.name}. Esta actualizacion es necesaria para seguir operando.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => context.go('/apps/${firstApp.id}'),
              icon: const Icon(Icons.system_update_alt_rounded),
              label: const Text('Actualizar ahora'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppListCard extends StatelessWidget {
  const _AppListCard({
    required this.app,
    required this.canRemoveFromDevice,
    required this.canDeleteFromStore,
  });

  final CorporateApp app;
  final bool canRemoveFromDevice;
  final bool canDeleteFromStore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlightColor = app.requiresImmediateUpdate
        ? colorScheme.error
        : app.primaryAction == AppPrimaryAction.update
            ? colorScheme.tertiary
            : colorScheme.outlineVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/apps/${app.id}'),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: highlightColor,
                width: app.requiresImmediateUpdate ? 5 : 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(app.description),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppStatusChip(app: app),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  app.installedVersion == null
                      ? 'No instalada'
                      : 'Instalada: ${app.installedVersion}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (app.latestVersion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Disponible: ${app.latestVersion!.version}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (app.requiresImmediateUpdate)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      app.isBelowMinimumSupportedVersion
                          ? 'Actualizacion obligatoria: la version instalada ya no cumple la version minima soportada.'
                          : 'Actualizacion obligatoria: instala la nueva version cuanto antes.',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if ((canRemoveFromDevice && app.isInstalled) ||
                    canDeleteFromStore) ...[
                  const SizedBox(height: 14),
                  _AdminAppActions(
                    app: app,
                    canRemoveFromDevice: canRemoveFromDevice,
                    canDeleteFromStore: canDeleteFromStore,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminAppActions extends ConsumerStatefulWidget {
  const _AdminAppActions({
    required this.app,
    required this.canRemoveFromDevice,
    required this.canDeleteFromStore,
  });

  final CorporateApp app;
  final bool canRemoveFromDevice;
  final bool canDeleteFromStore;

  @override
  ConsumerState<_AdminAppActions> createState() => _AdminAppActionsState();
}

class _AdminAppActionsState extends ConsumerState<_AdminAppActions> {
  bool _isDeleting = false;
  bool _isDeletingFromStore = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canRemoveFromDevice && widget.app.isInstalled)
          OutlinedButton.icon(
            onPressed:
                _isDeleting || _isDeletingFromStore ? null : _deleteFromDevice,
            icon: _isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.phone_android),
            label: const Text('Quitar de este dispositivo'),
          ),
        if (widget.canRemoveFromDevice &&
            widget.app.isInstalled &&
            widget.canDeleteFromStore)
          const SizedBox(height: 8),
        if (widget.canDeleteFromStore)
          OutlinedButton.icon(
            onPressed:
                _isDeleting || _isDeletingFromStore ? null : _deleteFromStore,
            icon: _isDeletingFromStore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.storefront_outlined),
            label: const Text('Retirar del catalogo'),
          ),
      ],
    );
  }

  Future<void> _deleteFromDevice() async {
    setState(() {
      _isDeleting = true;
    });

    try {
      final deviceProfile = await _resolveRegisteredDeviceProfile();
      final result = await ref.read(appRuntimeServiceProvider).uninstallApp(
            widget.app,
            deviceProfile: deviceProfile,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar la app: $error')),
        );
      }
    } finally {
      try {
        await ref.read(appsControllerProvider.notifier).refreshCatalog();
      } catch (_) {
        // The uninstall confirmation may still be open; refresh again on app resume.
      }

      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _deleteFromStore() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminar de tienda'),
            content: Text(
              'La app ${widget.app.name} dejara de estar disponible para todos los usuarios. Esta accion tambien elimina sus archivos publicados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() {
      _isDeletingFromStore = true;
    });

    try {
      await ref
          .read(appsControllerProvider.notifier)
          .deleteAppFromStore(widget.app.id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App eliminada de la tienda.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar de la tienda: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingFromStore = false;
        });
      }
    }
  }

  Future<DeviceProfile?> _resolveRegisteredDeviceProfile() async {
    try {
      return await ref.read(registeredDeviceProfileProvider.future);
    } catch (_) {
      return null;
    }
  }
}
