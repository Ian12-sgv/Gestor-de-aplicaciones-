import 'package:flutter/material.dart';

import '../../domain/corporate_app.dart';

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.app,
  });

  final CorporateApp app;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (app.primaryAction) {
      _ when app.requiresImmediateUpdate => (
          'Obligatoria',
          colorScheme.error,
          Icons.priority_high_rounded
        ),
      AppPrimaryAction.install => (
          'Instalar',
          colorScheme.primary,
          Icons.download_rounded
        ),
      AppPrimaryAction.update => (
          'Actualizar',
          colorScheme.tertiary,
          Icons.system_update_alt_rounded
        ),
      AppPrimaryAction.open => (
          'Abrir',
          colorScheme.secondary,
          Icons.open_in_new_rounded
        ),
      AppPrimaryAction.none => (
          'Sin cambios',
          colorScheme.outline,
          Icons.check_circle_outline_rounded
        ),
    };

    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
      backgroundColor: color.withValues(alpha: 0.08),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}
