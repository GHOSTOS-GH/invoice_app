// lib/screens/settings/security_page.dart
// Sécurité : changement de l'identifiant et du code admin, déconnexion.
// Les erreurs de AuthService.changeCredentials sont affichées telles quelles,
// avec le message d'avertissement sur l'irréversibilité du code.

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_snack.dart';
import '../../widgets/ui/app_text_field.dart';
import '../../widgets/ui/section_header.dart';

class SecurityPage extends StatefulWidget {
  final VoidCallback? onLogout;

  const SecurityPage({super.key, this.onLogout});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _obscure = true;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'Les deux codes ne correspondent pas.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final result = await _authService.changeCredentials(
      currentPassword: _currentPasswordController.text,
      newUsername: _usernameController.text,
      newPassword: _passwordController.text,
    );

    if (!mounted) return;

    switch (result) {
      case CredentialChangeResult.success:
        setState(() {
          _isSaving = false;
          _currentPasswordController.clear();
          _usernameController.clear();
          _passwordController.clear();
          _confirmController.clear();
        });
        AppSnack.success(context, 'Identifiant et code mis à jour');
        break;
      case CredentialChangeResult.wrongCurrentPassword:
        setState(() {
          _isSaving = false;
          _error = 'Le code actuel est incorrect.';
        });
        break;
      case CredentialChangeResult.invalidFormat:
        setState(() {
          _isSaving = false;
          _error = 'Identifiant : 3 à 20 caractères sans espace au début ni '
              'à la fin. Code : 4 à 12 caractères.';
        });
        break;
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    widget.onLogout?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(title: const Text('Sécurité')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: colors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Notez bien votre code : il ne peut pas être récupéré',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Identifiants administrateur',
              subtitle: 'Connexion requise une fois par jour',
              icon: Icons.lock_outline,
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                children: [
                  AppTextField(
                    controller: _currentPasswordController,
                    label: 'Code actuel',
                    icon: Icons.lock_outline,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    suffix: IconButton(
                      tooltip:
                          _obscure ? 'Afficher les codes' : 'Masquer les codes',
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Saisissez votre code actuel';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _usernameController,
                    label: 'Nouvel identifiant',
                    icon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final username = value?.trim() ?? '';
                      if (username.length < 3 || username.length > 20) {
                        return '3 à 20 caractères';
                      }
                      if (username != value) {
                        return 'Pas d\'espace au début ni à la fin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Nouveau code',
                    icon: Icons.password_outlined,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final code = value ?? '';
                      if (code.length < 4 || code.length > 12) {
                        return '4 à 12 caractères';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _confirmController,
                    label: 'Confirmation du nouveau code',
                    icon: Icons.password_outlined,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Confirmez le nouveau code';
                      }
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: colors.danger),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _error!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _submit,
                      child: _isSaving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'Session',
              subtitle: 'La connexion est demandée une fois par jour',
              icon: Icons.logout,
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                minVerticalPadding: AppSpacing.md,
                leading: Icon(Icons.logout, color: colors.danger),
                title: Text(
                  'Se déconnecter',
                  style: textTheme.bodyLarge?.copyWith(
                    color: colors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _logout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
