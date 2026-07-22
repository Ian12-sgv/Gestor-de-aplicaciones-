import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Actualiza tu contrasena',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Por seguridad, crea una contrasena nueva antes de continuar.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _currentPasswordController,
                          decoration: const InputDecoration(
                            labelText: 'Contrasena actual',
                          ),
                          obscureText: true,
                          validator: _requiredPassword,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _newPasswordController,
                          decoration: const InputDecoration(
                            labelText: 'Nueva contrasena',
                            helperText:
                                'Minimo 8 caracteres, mayuscula, minuscula, numero y simbolo.',
                          ),
                          obscureText: true,
                          validator: _validateNewPassword,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar nueva contrasena',
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value != _newPasswordController.text) {
                              return 'Las contrasenas no coinciden';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: isLoading ? null : _submit,
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Guardar y continuar'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: isLoading
                              ? null
                              : () => ref
                                  .read(authControllerProvider.notifier)
                                  .logout(),
                          child: const Text('Cerrar sesion'),
                        ),
                        if (authState.hasError) ...[
                          const SizedBox(height: 16),
                          Text(
                            'No se pudo actualizar la contrasena. Revisa los datos e intenta otra vez.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _requiredPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa tu contrasena actual';
    }

    return null;
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';

    if (password.length < 8) {
      return 'Debe tener al menos 8 caracteres';
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Incluye una letra minuscula';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Incluye una letra mayuscula';
    }

    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Incluye un numero';
    }

    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Incluye un simbolo';
    }

    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await ref.read(authControllerProvider.notifier).changePassword(
          currentPassword: _currentPasswordController.text,
          newPassword: _newPasswordController.text,
        );
  }
}
