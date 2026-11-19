import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../device/domain/device_profile.dart';
import '../../device/presentation/device_controller.dart';
import '../data/app_runtime_service.dart';
import '../data/android_app_bridge.dart';
import '../domain/corporate_app.dart';
import 'apps_controller.dart';
import 'widgets/app_avatar_tile.dart';

class AppDetailScreen extends ConsumerStatefulWidget {
  const AppDetailScreen({
    super.key,
    required this.appId,
  });

  final String appId;

  @override
  ConsumerState<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends ConsumerState<AppDetailScreen> {
  bool get _catalogRemovalEnabled => false;
  late final AppLifecycleListener _lifecycleListener;
  bool _isSubmitting = false;

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
    final appAsync = ref.watch(appDetailProvider(widget.appId));
    final installEnvironmentAsync = ref.watch(installEnvironmentInfoProvider);
    const canRemoveFromDevice = true;
    final activeDownloads =
        ref.watch(appRuntimeServiceProvider).activeDownloads;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles de la aplicación'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(),
        ),
      ),
      body: appAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudo cargar la app: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppPalette.muted),
            ),
          ),
        ),
        data: (app) {
          final action = app.primaryAction;
          final latestVersion = app.latestVersion;
          final actionLabel = _resolvePrimaryActionLabel(app);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            children: [
              _AppHeader(app: app),
              const SizedBox(height: 24),
              _AppStatsCard(app: app),
              if (app.requiresImmediateUpdate) ...[
                const SizedBox(height: 16),
                _MandatoryUpdateBanner(app: app),
              ],
              if (action == AppPrimaryAction.install ||
                  action == AppPrimaryAction.update) ...[
                const SizedBox(height: 16),
                installEnvironmentAsync.when(
                  data: (installEnvironment) => _InstallRequirementsCard(
                    installEnvironment: installEnvironment,
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                ),
              ],
              const SizedBox(height: 28),
              const Text(
                'Novedades',
                style: TextStyle(
                  color: AppPalette.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                latestVersion == null || latestVersion.changelog.trim().isEmpty
                    ? 'Sin novedades disponibles.'
                    : latestVersion.changelog,
                style: const TextStyle(
                  color: AppPalette.muted,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: app.requiresImmediateUpdate
                    ? FilledButton.styleFrom(
                        backgroundColor: AppPalette.danger,
                      )
                    : null,
                onPressed: _isSubmitting || action == AppPrimaryAction.none
                    ? null
                    : () => _handlePrimaryAction(app),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_primaryActionIcon(action), size: 20),
                label: Text(actionLabel),
              ),
              ValueListenableBuilder<Map<String, double?>>(
                valueListenable: activeDownloads,
                builder: (context, downloads, _) {
                  if (!downloads.containsKey(app.packageName)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _DownloadProgress(
                      progress: downloads[app.packageName],
                    ),
                  );
                },
              ),
              if (canRemoveFromDevice && app.isInstalled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : () => _uninstallApp(app),
                  icon: const Icon(Icons.phone_android_rounded, size: 20),
                  label: const Text('Quitar de este dispositivo'),
                ),
              ],
              if (_catalogRemovalEnabled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : () => _deleteFromStore(app),
                  icon: const Icon(Icons.storefront_outlined, size: 20),
                  label: const Text('Retirar del catálogo'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static IconData _primaryActionIcon(AppPrimaryAction action) {
    return switch (action) {
      AppPrimaryAction.install => Icons.download_rounded,
      AppPrimaryAction.update => Icons.system_update_alt_rounded,
      AppPrimaryAction.open => Icons.open_in_new_rounded,
      AppPrimaryAction.none => Icons.check_circle_outline_rounded,
    };
  }

  Future<void> _handlePrimaryAction(CorporateApp app) async {
    final runtimeService = ref.read(appRuntimeServiceProvider);
    final deviceProfile = await _resolveRegisteredDeviceProfile();

    await _runAction(() async {
      return switch (app.primaryAction) {
        AppPrimaryAction.install ||
        AppPrimaryAction.update =>
          runtimeService.downloadAndInstall(
            app,
            deviceProfile: deviceProfile,
          ),
        AppPrimaryAction.open => runtimeService.openInstalledApp(
            app,
            deviceProfile: deviceProfile,
          ),
        AppPrimaryAction.none => const AppActionResult(
            success: false,
            message: 'No hay acciones disponibles para esta app.',
          ),
      };
    });
  }

  Future<void> _uninstallApp(CorporateApp app) async {
    final deviceProfile = await _resolveRegisteredDeviceProfile();
    await _runAction(() {
      return ref.read(appRuntimeServiceProvider).uninstallApp(
            app,
            deviceProfile: deviceProfile,
          );
    });
  }

  Future<void> _deleteFromStore(CorporateApp app) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminar de tienda'),
            content: Text(
              'La app ${app.name} dejara de estar disponible para todos los usuarios. Esta accion tambien elimina sus archivos publicados.',
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
      _isSubmitting = true;
    });

    try {
      await ref
          .read(appsControllerProvider.notifier)
          .deleteAppFromStore(app.id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App eliminada de la tienda.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar de la tienda: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _runAction(Future<AppActionResult> Function() action) async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await action();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo completar la accion: $error')),
        );
      }
    } finally {
      try {
        await _refreshAppState();
      } catch (_) {
        // The action feedback is more important than failing the local refresh.
      }

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _handleResume() {
    ref.invalidate(appDetailProvider(widget.appId));
    ref.read(appsControllerProvider.notifier).refreshCatalog();
  }

  Future<void> _refreshAppState() async {
    ref.invalidate(appDetailProvider(widget.appId));
    await ref.read(appsControllerProvider.notifier).refreshCatalog();
  }

  Future<DeviceProfile?> _resolveRegisteredDeviceProfile() async {
    try {
      return await ref.read(registeredDeviceProfileProvider.future);
    } catch (_) {
      return null;
    }
  }

  String _resolvePrimaryActionLabel(CorporateApp app) {
    if (app.requiresImmediateUpdate) {
      return 'Actualizar ahora';
    }

    return switch (app.primaryAction) {
      AppPrimaryAction.install => 'Instalar',
      AppPrimaryAction.update => 'Actualizar',
      AppPrimaryAction.open => 'Abrir',
      AppPrimaryAction.none => 'Sin acciones',
    };
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({
    required this.progress,
  });

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress?.clamp(0, 1).toDouble();
    final percentage =
        safeProgress == null ? null : (safeProgress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: safeProgress),
        const SizedBox(height: 8),
        Text(
          percentage == null
              ? 'Descargando app...'
              : 'Descargando app $percentage%',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.app});

  final CorporateApp app;

  @override
  Widget build(BuildContext context) {
    final trimmedName = app.name.trim();
    final initial =
        trimmedName.isEmpty ? '?' : trimmedName.characters.first.toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppAvatarTile(
          label: initial,
          colorSeed: app.id,
          imageUrl: app.iconPath,
          size: 88,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.name,
                style: const TextStyle(
                  color: AppPalette.ink,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'pdb Corporativo',
                style: TextStyle(
                  color: AppPalette.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                app.packageName,
                style: const TextStyle(
                  color: AppPalette.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppStatsCard extends StatelessWidget {
  const _AppStatsCard({required this.app});

  final CorporateApp app;

  @override
  Widget build(BuildContext context) {
    final status = !app.isInstalled
        ? 'Disponible'
        : app.hasUpdateAvailable
            ? 'Desactualizada'
            : 'Instalada';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  _StatCell(label: 'Estado', value: status),
                  const VerticalDivider(width: 1),
                  _StatCell(
                    label: 'Versión',
                    value: app.latestVersion?.version ?? '—',
                  ),
                  const VerticalDivider(width: 1),
                  _StatCell(
                    label: 'Prioridad',
                    value: app.requiresImmediateUpdate ? 'Alta' : 'Normal',
                    valueColor: app.requiresImmediateUpdate
                        ? AppPalette.danger
                        : AppPalette.ink,
                  ),
                ],
              ),
            ),
            if (app.isInstalled &&
                app.installedVersion != null &&
                app.hasUpdateAvailable) ...[
              const SizedBox(height: 12),
              Text(
                'Versión en uso: ${app.installedVersion}',
                style: const TextStyle(color: AppPalette.muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.valueColor = AppPalette.ink,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: AppPalette.muted, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.border,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final Color border;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppPalette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DefaultTextStyle.merge(
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallRequirementsCard extends StatelessWidget {
  const _InstallRequirementsCard({
    required this.installEnvironment,
  });

  final InstallEnvironmentInfo installEnvironment;

  @override
  Widget build(BuildContext context) {
    final hasUnknownSourcesPermission =
        installEnvironment.canInstallUnknownApps;
    final hasInstaller = installEnvironment.installerAvailable;
    final isReady = hasUnknownSourcesPermission && hasInstaller;

    return _NoticeCard(
      icon: isReady ? Icons.verified_outlined : Icons.shield_outlined,
      iconColor: isReady ? AppPalette.primary : AppPalette.danger,
      background: isReady ? AppPalette.mint : AppPalette.blush,
      border: isReady ? AppPalette.mintBorder : AppPalette.blushBorder,
      title: isReady ? 'Listo para instalar' : 'Permiso necesario',
      children: [
        Text(
          !hasInstaller
              ? 'No se encontró una app del sistema para completar la instalación.'
              : hasUnknownSourcesPermission
                  ? 'Este dispositivo permite instalar apps corporativas. Al continuar se abrirá el instalador del sistema.'
                  : 'Android solicitará permiso para instalar esta aplicación. Al continuar se abrirá el instalador del sistema.',
        ),
      ],
    );
  }
}

class _MandatoryUpdateBanner extends StatelessWidget {
  const _MandatoryUpdateBanner({
    required this.app,
  });

  final CorporateApp app;

  @override
  Widget build(BuildContext context) {
    final latestVersion = app.latestVersion;

    return _NoticeCard(
      icon: Icons.warning_amber_rounded,
      iconColor: AppPalette.danger,
      background: AppPalette.blush,
      border: AppPalette.blushBorder,
      title: 'Actualización obligatoria',
      children: [
        Text(
          app.isBelowMinimumSupportedVersion
              ? 'La versión instalada ya no cumple con la versión mínima soportada. Debes actualizar antes de seguir usando esta app.'
              : 'Hay una actualización importante. Instálala para mantener la app al día.',
        ),
        if (latestVersion != null) ...[
          const SizedBox(height: 6),
          Text(
            'Versión requerida: ${latestVersion.version}',
            style: const TextStyle(
              color: AppPalette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
