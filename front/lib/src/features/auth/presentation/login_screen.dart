import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _lastIdentifierKey = 'login.lastIdentifier';

  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadLastIdentifier();
    _identifierController.addListener(_saveCurrentIdentifier);
  }

  @override
  void dispose() {
    _identifierController.removeListener(_saveCurrentIdentifier);
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: AppPalette.loginBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A0B3D38),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _LoginBrandHeader(),
                          const SizedBox(height: 28),
                          const _FieldLabel('Correo corporativo'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _identifierController,
                            decoration: const InputDecoration(
                              hintText: 'nombre@empresa.com',
                            ),
                            autofillHints: const <String>[
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingresa tu correo o usuario';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          const _FieldLabel('Contraseña'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              hintText: 'Tu contraseña',
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppPalette.ink,
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
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!isLoading) {
                                _submit();
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Ingresa tu contraseña';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: isLoading ? null : _submit,
                            icon: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login_rounded, size: 20),
                            label: Text(
                              isLoading
                                  ? 'Verificando acceso...'
                                  : 'Iniciar sesión',
                            ),
                          ),
                          if (authState.hasError) ...[
                            const SizedBox(height: 16),
                            const _LoginErrorMessage(),
                          ],
                          const SizedBox(height: 22),
                          const _SecureAccessNote(),
                        ],
                      ),
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

    await _saveCurrentIdentifier();
    await ref.read(authControllerProvider.notifier).login(
          identifier: _identifierController.text.trim(),
          password: _passwordController.text,
        );
  }

  Future<void> _loadLastIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.remove('login.lastPassword');
    final lastIdentifier = prefs.getString(_lastIdentifierKey);

    if (!mounted) {
      return;
    }

    if (lastIdentifier != null && lastIdentifier.isNotEmpty) {
      _identifierController.text = lastIdentifier;
    }
  }

  Future<void> _saveCurrentIdentifier() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final identifier = _identifierController.text.trim();

    if (identifier.isNotEmpty) {
      await prefs.setString(_lastIdentifierKey, identifier);
    }
  }
}

class _LoginBrandHeader extends StatelessWidget {
  const _LoginBrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/branding/pdbstore_logo.png',
          width: 84,
          height: 84,
          semanticLabel: 'Logo de PDBStore',
        ),
        const SizedBox(height: 20),
        const Text(
          'pdb Store',
          style: TextStyle(
            color: AppPalette.ink,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Accede al catálogo interno de aplicaciones corporativas.',
          style: TextStyle(
            color: AppPalette.muted,
            fontSize: 15,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppPalette.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _LoginErrorMessage extends StatelessWidget {
  const _LoginErrorMessage();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.blush,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.blushBorder),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: AppPalette.danger),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No fue posible iniciar sesión. Revisa tus datos o tu conexión e intenta de nuevo.',
                style: TextStyle(color: AppPalette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecureAccessNote extends StatelessWidget {
  const _SecureAccessNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 18,
          color: AppPalette.muted,
        ),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            'Acceso protegido para aplicaciones corporativas.',
            style: TextStyle(color: AppPalette.muted, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
