import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_controller.dart';

class AppAvatarTile extends ConsumerStatefulWidget {
  const AppAvatarTile({
    super.key,
    required this.label,
    required this.colorSeed,
    required this.imageUrl,
    this.size = 64,
  });

  final String label;
  final String colorSeed;
  final String imageUrl;
  final double size;

  @override
  ConsumerState<AppAvatarTile> createState() => _AppAvatarTileState();
}

class _AppAvatarTileState extends ConsumerState<AppAvatarTile> {
  Future<Uint8List>? _iconBytes;

  @override
  void initState() {
    super.initState();
    _iconBytes = _loadIcon(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant AppAvatarTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _iconBytes = _loadIcon(widget.imageUrl);
    }
  }

  Future<Uint8List>? _loadIcon(String imageUrl) {
    final iconPath = imageUrl.trim();
    if (iconPath.isEmpty) {
      return null;
    }

    return ref
        .read(apiClientProvider)
        .dio
        .get<List<int>>(
          iconPath,
          options: Options(
            responseType: ResponseType.bytes,
            extra: const <String, Object>{
              'skipAuth': true,
              'skipRefresh': true,
            },
          ),
        )
        .then((response) {
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('El icono no contiene datos.');
      }
      return Uint8List.fromList(bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final iconBytes = _iconBytes;

    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppPalette.tileColorFor(widget.colorSeed),
        borderRadius: BorderRadius.circular(widget.size * 0.26),
      ),
      clipBehavior: Clip.antiAlias,
      child: iconBytes == null
          ? _AvatarLabel(label: widget.label, size: widget.size)
          : FutureBuilder<Uint8List>(
              future: iconBytes,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  return _AvatarLabel(label: widget.label, size: widget.size);
                }

                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _AvatarLabel(label: widget.label, size: widget.size),
                );
              },
            ),
    );
  }
}

class _AvatarLabel extends StatelessWidget {
  const _AvatarLabel({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppPalette.primary,
        fontSize: size * 0.36,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
