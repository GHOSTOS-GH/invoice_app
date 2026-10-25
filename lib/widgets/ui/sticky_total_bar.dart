// lib/widgets/ui/sticky_total_bar.dart

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'amount_text.dart';

/// Barre fixe de bas d'écran : total à payer, nombre d'articles et action
/// principale en pleine largeur.
class StickyTotalBar extends StatelessWidget {
  final int total;
  final int itemCount;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final bool isLoading;
  final Widget? secondary;

  const StickyTotalBar({
    super.key,
    required this.total,
    required this.itemCount,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon = Icons.check_circle_outline,
    this.isLoading = false,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final articles = '$itemCount article${itemCount > 1 ? 's' : ''}';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total à payer',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AmountText(
                          total,
                          size: AmountSize.large,
                          color: colors.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    articles,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
              if (secondary != null) ...[
                const SizedBox(height: AppSpacing.md),
                secondary!,
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: isLoading ? null : onAction,
                icon: isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : Icon(actionIcon, size: 20),
                label: Text(isLoading ? 'Enregistrement...' : actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
