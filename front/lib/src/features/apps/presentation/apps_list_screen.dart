import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/domain/app_user.dart';
import '../../device/domain/device_profile.dart';
import '../../device/presentation/device_controller.dart';
import '../data/android_app_bridge.dart';
import '../data/app_runtime_service.dart';
import '../domain/corporate_app.dart';
import 'apps_controller.dart';
import 'widgets/app_avatar_tile.dart';

class AppsListScreen extends ConsumerWidget {
  bool get _showLogoutControl => false;
  const AppsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsState = ref.watch(appsControllerProvider);
    final installEnvironmentAsync = ref.watch(installEnvironmentInfoProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 20,
        title: const _StoreTitle(),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: () =>
                ref.read(appsControllerProvider.notifier).refreshCatalog(),
            icon: const Icon(Icons.sync_rounded),
          ),
          if (_showLogoutControl)
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: null,
              icon: const Icon(Icons.logout_rounded),
            ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(appsControllerProvider.notifier).refreshCatalog(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            installEnvironmentAsync.when(
              data: (installEnvironment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InstallPermissionCard(
                  installEnvironment: installEnvironment,
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),
            ...appsState.when(
              loading: () => const [
                _CatalogHeader(appCount: null),
                Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, stackTrace) => [
                const _CatalogHeader(appCount: null),
                const SizedBox(height: 16),
                _CatalogMessage(
                  icon: Icons.cloud_off_rounded,
                  message: 'No se pudo cargar el catálogo: $error',
                ),
              ],
              data: (apps) => _buildCatalog(apps),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCatalog(List<CorporateApp> apps) {
    final sortedApps = _sortApps(apps);
    final mandatoryApps = sortedApps
        .where((app) => app.requiresImmediateUpdate)
        .toList(growable: false);

    return [
      if (mandatoryApps.isNotEmpty) ...[
        _MandatoryUpdatesSummaryCard(apps: mandatoryApps),
        const SizedBox(height: 24),
      ],
      _CatalogHeader(appCount: sortedApps.length),
      const SizedBox(height: 16),
      if (sortedApps.isEmpty)
        const _CatalogMessage(
          icon: Icons.inventory_2_outlined,
          message: 'Todavía no hay aplicaciones disponibles para ti.',
        ),
      for (final (index, app) in sortedApps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _AppListCard(app: app, position: index + 1),
        ),
    ];
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

class _StoreTitle extends StatelessWidget {
  const _StoreTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/branding/pdbstore_logo.png',
          width: 44,
          height: 44,
          semanticLabel: 'Logo de PDBStore',
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'pdb Store',
              style: TextStyle(
                color: AppPalette.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Aplicaciones corporativas',
              style: TextStyle(
                color: AppPalette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class CurrentUserCard extends StatelessWidget {
  const CurrentUserCard({super.key, required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final currentUser = user;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.mint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.mintBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const _IconBubble(
              icon: Icons.person_outline_rounded,
              circular: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Eyebrow('Sesión activa', color: AppPalette.muted),
                  const SizedBox(height: 4),
                  Text.rich(
                    currentUser == null
                        ? const TextSpan(text: 'Usuario no identificado')
                        : TextSpan(
                            children: [
                              TextSpan(
                                text: currentUser.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: ' (${currentUser.username})',
                                style: const TextStyle(
                                  color: AppPalette.muted,
                                ),
                              ),
                            ],
                          ),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.ink,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppPalette.online,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallPermissionCard extends ConsumerStatefulWidget {
  const _InstallPermissionCard({
    required this.installEnvironment,
  });

  final InstallEnvironmentInfo installEnvironment;

  @override
  ConsumerState<_InstallPermissionCard> createState() =>
      _InstallPermissionCardState();
}

class _InstallPermissionCardState
    extends ConsumerState<_InstallPermissionCard> {
  bool _isOpeningSettings = false;

  @override
  Widget build(BuildContext context) {
    final isReady = widget.installEnvironment.canInstallUnknownApps;
    final canOpenSettings = widget.installEnvironment.settingsAvailable;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.sky,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.skyBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconBubble(
                  icon: isReady
                      ? Icons.check_rounded
                      : Icons.verified_user_outlined,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReady
                            ? 'Instalaciones preparadas'
                            : 'Prepara las instalaciones',
                        style: const TextStyle(
                          color: AppPalette.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isReady
                            ? 'El permiso está listo. Ya puedes instalar aplicaciones desde el catálogo.'
                            : 'Activa una vez el permiso de la Store para instalar apps corporativas sin repetir este paso.',
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isReady) ...[
            const Divider(color: AppPalette.skyBorder),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: canOpenSettings && !_isOpeningSettings
                    ? _openSettings
                    : null,
                icon: _isOpeningSettings
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.tune_rounded, size: 20),
                label: const Text('Preparar instalaciones'),
              ),
            ),
          ],
        ],
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
          content: Text('No se pudo abrir el permiso de instalación.'),
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
    final firstApp = apps.first;
    final remainingApps = apps.length - 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.blush,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.blushBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _IconBubble(
                  icon: Icons.warning_amber_rounded,
                  color: AppPalette.danger,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        apps.length == 1
                            ? 'Hay 1 app con actualización obligatoria'
                            : 'Hay ${apps.length} apps con actualización obligatoria',
                        style: const TextStyle(
                          color: AppPalette.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        remainingApps > 0
                            ? 'Empieza por ${firstApp.name}. Después podrás revisar las otras $remainingApps pendientes.'
                            : 'Empieza por ${firstApp.name}. Esta actualización es necesaria para seguir operando.',
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.danger,
              ),
              onPressed: () => context.go('/apps/${firstApp.id}'),
              icon: const Icon(Icons.system_update_alt_rounded, size: 20),
              label: const Text('Actualizar ahora'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({required this.appCount});

  final int? appCount;

  @override
  Widget build(BuildContext context) {
    final count = appCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('Catálogo', color: AppPalette.primary),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Flexible(
              child: Text(
                'Aplicaciones disponibles',
                style: TextStyle(
                  color: AppPalette.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                count == 1 ? '1 app' : '$count apps',
                style: const TextStyle(color: AppPalette.muted, fontSize: 14),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: AppPalette.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppPalette.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppListCard extends ConsumerStatefulWidget {
  const _AppListCard({
    required this.app,
    required this.position,
  });

  final CorporateApp app;
  final int position;

  @override
  ConsumerState<_AppListCard> createState() => _AppListCardState();
}

class _AppListCardState extends ConsumerState<_AppListCard> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final activeDownloads =
        ref.watch(appRuntimeServiceProvider).activeDownloads;

    return ValueListenableBuilder<Map<String, double?>>(
      valueListenable: activeDownloads,
      builder: (context, downloads, _) => _buildCard(
        context,
        isDownloading: downloads.containsKey(widget.app.packageName),
        downloadProgress: downloads[widget.app.packageName],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool isDownloading,
    required double? downloadProgress,
  }) {
    final app = widget.app;
    final latestVersion = app.latestVersion;
    final showsInstalledVersion = app.isInstalled &&
        app.installedVersion != null &&
        app.installedVersion != latestVersion?.version;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: app.requiresImmediateUpdate
              ? AppPalette.blushBorder
              : AppPalette.border,
        ),
      ),
      child: InkWell(
        onTap: () => context.go('/apps/${app.id}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatarTile(
                label: '${widget.position}',
                colorSeed: app.id,
                imageUrl: app.iconPath,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      app.name,
                      style: const TextStyle(
                        color: AppPalette.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      app.packageName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 13,
                      ),
                    ),
                    if (app.requiresImmediateUpdate) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Actualización obligatoria',
                        style: TextStyle(
                          color: AppPalette.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _Eyebrow(
                                'Versión disponible',
                                color: AppPalette.muted,
                                letterSpacing: 0.2,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                latestVersion?.version ?? '—',
                                style: const TextStyle(
                                  color: AppPalette.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (showsInstalledVersion)
                                Text(
                                  'Instalada: ${app.installedVersion}',
                                  style: const TextStyle(
                                    color: AppPalette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (app.primaryAction != AppPrimaryAction.none)
                          _CompactActionButton(
                            label: _actionLabel(app),
                            isBusy: _isBusy || isDownloading,
                            isUrgent: app.requiresImmediateUpdate,
                            onPressed: _runPrimaryAction,
                          ),
                      ],
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: downloadProgress),
                      const SizedBox(height: 6),
                      Text(
                        downloadProgress == null
                            ? 'Descargando...'
                            : 'Descargando ${(downloadProgress * 100).round()}%',
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _actionLabel(CorporateApp app) {
    return switch (app.primaryAction) {
      AppPrimaryAction.install => 'Instalar',
      AppPrimaryAction.update => 'Actualizar',
      AppPrimaryAction.open => 'Abrir',
      AppPrimaryAction.none => '',
    };
  }

  Future<void> _runPrimaryAction() async {
    final app = widget.app;
    setState(() {
      _isBusy = true;
    });

    try {
      final runtimeService = ref.read(appRuntimeServiceProvider);
      final deviceProfile = await _resolveRegisteredDeviceProfile();
      final result = switch (app.primaryAction) {
        AppPrimaryAction.install ||
        AppPrimaryAction.update =>
          await runtimeService.downloadAndInstall(
            app,
            deviceProfile: deviceProfile,
            onDownloadProgress: (_) {},
          ),
        AppPrimaryAction.open => await runtimeService.openInstalledApp(
            app,
            deviceProfile: deviceProfile,
          ),
        AppPrimaryAction.none => const AppActionResult(
            success: false,
            message: 'No hay acciones disponibles para esta app.',
          ),
      };

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo completar la acción: $error')),
        );
      }
    } finally {
      try {
        await ref.read(appsControllerProvider.notifier).refreshCatalog();
      } catch (_) {
        // The system installer may still be open; the catalog refreshes on resume.
      }

      if (mounted) {
        setState(() {
          _isBusy = false;
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

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.label,
    required this.isBusy,
    required this.isUrgent,
    required this.onPressed,
  });

  final String label;
  final bool isBusy;
  final bool isUrgent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isBusy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: isUrgent ? AppPalette.danger : AppPalette.primary,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({
    required this.icon,
    this.circular = false,
    this.color = AppPalette.primary,
  });

  final IconData icon;
  final bool circular;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(
    this.text, {
    required this.color,
    this.letterSpacing = 0.6,
  });

  final String text;
  final Color color;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
      ),
    );
  }
}
