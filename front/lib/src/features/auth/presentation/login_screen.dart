import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _lastIdentifierKey = 'login.lastIdentifier';
  static const _lastPasswordKey = 'login.lastPassword';

  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadLastCredentials();
    _identifierController.addListener(_saveCurrentCredentials);
    _passwordController.addListener(_saveCurrentCredentials);
  }

  @override
  void dispose() {
    _identifierController.removeListener(_saveCurrentCredentials);
    _passwordController.removeListener(_saveCurrentCredentials);
    _identifierController.dispose();
    _passwordController.dispose();
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
                          'pdb Store',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Accede al catalogo interno de apps corporativas.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _identifierController,
                          decoration: const InputDecoration(
                            labelText: 'Correo o usuario',
                          ),
                          autofillHints: const <String>[
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu correo o usuario';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Contrasena',
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Mostrar contrasena'
                                  : 'Ocultar contrasena',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          autofillHints: const <String>[
                            AutofillHints.password,
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Ingresa una contrasena';
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
                              : const Text('Iniciar sesion'),
                        ),
                        if (authState.hasError) ...[
                          const SizedBox(height: 16),
                          Text(
                            'No fue posible iniciar sesion. Revisa el backend o activa el modo demo manualmente.',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await _saveCurrentCredentials();
    await ref.read(authControllerProvider.notifier).login(
          identifier: _identifierController.text.trim(),
          password: _passwordController.text,
        );
  }

  Future<void> _loadLastCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final lastIdentifier = prefs.getString(_lastIdentifierKey);
    final lastPassword = prefs.getString(_lastPasswordKey);

    if (!mounted) {
      return;
    }

    if (lastIdentifier != null && lastIdentifier.isNotEmpty) {
      _identifierController.text = lastIdentifier;
    }

    if (lastPassword != null && lastPassword.isNotEmpty) {
      _passwordController.text = lastPassword;
    }
  }

  Future<void> _saveCurrentCredentials() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (identifier.isNotEmpty) {
      await prefs.setString(_lastIdentifierKey, identifier);
    }

    if (password.isNotEmpty) {
      await prefs.setString(_lastPasswordKey, password);
    }
  }
}
