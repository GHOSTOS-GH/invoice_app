// lib/screens/settings/appearance_page.dart
// Choix du thème : Système, Clair ou Sombre (persisté).

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_snack.dart';
import '../../widgets/ui/section_header.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  Future<void> _select(BuildContext context, ThemeMode mode) async {
    await ThemeController.instance.setMode(mode);
    if (!context.mounted) return;
    AppSnack.neutral(
      context,
      'Thème : ${ThemeController.labelOf(mode)}',
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(title: const Text('Apparence')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.instance,
        builder: (context, mode, _) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const SectionHeader(
                title: 'Thème de l\'application',
                subtitle: 'Le mode Système suit le réglage du téléphone.',
                icon: Icons.palette_outlined,
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: EdgeInsets.zero,
                child: RadioGroup<ThemeMode>(
                  groupValue: mode,
                  onChanged: (selected) {
                    if (selected == null) return;
                    _select(context, selected);
                  },
                  child: Column(
                    children: [
                      for (final option in ThemeMode.values)
                        RadioListTile<ThemeMode>(
                          value: option,
                          activeColor: colors.primary,
                          title: Text(
                            ThemeController.labelOf(option),
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: colors.textStrong),
                          ),
                          subtitle: option == ThemeMode.system
                              ? Text(
                                  'Suit le mode clair / sombre du téléphone',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.textMuted),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
