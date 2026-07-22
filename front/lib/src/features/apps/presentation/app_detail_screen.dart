import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../device/domain/device_profile.dart';
import '../../device/presentation/device_controller.dart';
import '../data/app_runtime_service.dart';
import '../data/android_app_bridge.dart';
import '../domain/corporate_app.dart';
import 'apps_controller.dart';

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
  late final AppLifecycleListener _lifecycleListener;
  bool _isSubmitting = false;
  bool _showDownloadProgress = false;
  double? _downloadProgress;

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
    final authState = ref.watch(authControllerProvider);
    final user = authState.valueOrNull?.user;
    final canRemoveFromDevice = user != null;
    final canDeleteFromStore = user?.canDeleteAppsFromStore ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Aplicacion')),
      body: appAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('No se pudo cargar la app: $error'),
        ),
        data: (app) {
          final action = app.primaryAction;
          final latestVersion = app.latestVersion;
          final actionLabel = _resolvePrimaryActionLabel(app);

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(app.name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(app.description),
              if (app.requiresImmediateUpdate) ...[
                const SizedBox(height: 24),
                _MandatoryUpdateBanner(app: app),
              ],
              const SizedBox(height: 24),
              _InfoRow(
                label: 'Estado',
                value: app.isInstalled ? 'Instalada' : 'No instalada',
              ),
              if (app.installedVersion != null)
                _InfoRow(
                  label: 'En uso',
                  value: app.installedVersion!,
                ),
              _InfoRow(
                label: 'Disponible',
                value: latestVersion?.version ?? 'Sin version disponible',
              ),
              _InfoRow(
                label: 'Prioridad',
                value: app.requiresImmediateUpdate
                    ? 'Requiere actualizacion'
                    : 'Normal',
              ),
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
              const SizedBox(height: 24),
              Text('Novedades', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                latestVersion == null || latestVersion.changelog.trim().isEmpty
                    ? 'Sin novedades disponibles.'
                    : latestVersion.changelog,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSubmitting || action == AppPrimaryAction.none
                    ? null
                    : () => _handlePrimaryAction(app),
                child: _ActionLabel(
                  isBusy: _isSubmitting,
                  label: actionLabel,
                ),
              ),
              if (_showDownloadProgress) ...[
                const SizedBox(height: 12),
                _DownloadProgress(progress: _downloadProgress),
              ],
              if ((canRemoveFromDevice && app.isInstalled) ||
                  canDeleteFromStore) ...[
                const SizedBox(height: 12),
                if (canRemoveFromDevice && app.isInstalled)
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : () => _uninstallApp(app),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Quitar de este dispositivo'),
                  ),
                if (canRemoveFromDevice &&
                    app.isInstalled &&
                    canDeleteFromStore)
                  const SizedBox(height: 12),
                if (canDeleteFromStore)
                  OutlinedButton.icon(
                    onPressed:
                        _isSubmitting ? null : () => _deleteFromStore(app),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Retirar del catalogo'),
                  ),
              ],
            ],
          );
        },
      ),
    );
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
            onDownloadProgress: _updateDownloadProgress,
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
          _showDownloadProgress = false;
          _downloadProgress = null;
        });
      }
    }
  }

  void _updateDownloadProgress(double? progress) {
    if (!mounted) {
      return;
    }

    setState(() {
      _showDownloadProgress = true;
      _downloadProgress = progress;
    });
  }

  Future<void> _runAction(Future<AppActionResult> Function() action) async {
    setState(() {
      _isSubmitting = true;
      _showDownloadProgress = false;
      _downloadProgress = null;
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
          _showDownloadProgress = false;
          _downloadProgress = null;
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

class _InstallRequirementsCard extends StatelessWidget {
  const _InstallRequirementsCard({
    required this.installEnvironment,
  });

  final InstallEnvironmentInfo installEnvironment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasUnknownSourcesPermission =
        installEnvironment.canInstallUnknownApps;
    final hasInstaller = installEnvironment.installerAvailable;
    final severityColor = hasUnknownSourcesPermission && hasInstaller
        ? colorScheme.secondary
        : colorScheme.error;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: severityColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: severityColor.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasUnknownSourcesPermission && hasInstaller
                  ? 'Listo para instalar'
                  : 'Permiso necesario',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              hasUnknownSourcesPermission
                  ? 'Este dispositivo permite instalar apps corporativas.'
                  : 'Activa el permiso de instalacion cuando Android lo solicite.',
            ),
            const SizedBox(height: 4),
            Text(
              hasInstaller
                  ? 'Al continuar se abrira el instalador del sistema.'
                  : 'No se encontro una app del sistema para completar la instalacion.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel({
    required this.isBusy,
    required this.label,
  });

  final bool isBusy;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!isBusy) {
      return Text(label);
    }

    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
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
    final colorScheme = Theme.of(context).colorScheme;
    final latestVersion = app.latestVersion;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.24)),
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
                    'Actualizacion obligatoria',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              app.isBelowMinimumSupportedVersion
                  ? 'La version instalada ya no cumple con la version minima soportada. Debes actualizar antes de seguir usando esta app.'
                  : 'Hay una actualizacion importante. Instalala para mantener la app al dia.',
            ),
            if (latestVersion != null) ...[
              const SizedBox(height: 10),
              Text(
                'Version requerida: ${latestVersion.version}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
