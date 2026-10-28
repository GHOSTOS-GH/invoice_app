// lib/widgets/ui/amount_text.dart

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

enum AmountSize { hero, large, medium, small }

/// Montant FCFA (entier) formaté avec le séparateur insécable, jamais décimal.
class AmountText extends StatelessWidget {
  final int amount;
  final AmountSize size;
  final Color? color;
  final bool showCurrency;
  final TextAlign? textAlign;
  final bool muted;

  const AmountText(
    this.amount, {
    super.key,
    this.size = AmountSize.medium,
    this.color,
    this.showCurrency = true,
    this.textAlign,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final base = Theme.of(context).textTheme;
    final style = switch (size) {
      AmountSize.hero => base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      AmountSize.large => base.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      AmountSize.medium => base.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      AmountSize.small => base.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
    };

    final text = showCurrency ? formatCurrency(amount) : formatNumber(amount);

    return Text(
      text,
      textAlign: textAlign,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(
        color: color ?? (muted ? colors.textMuted : colors.textStrong),
      ),
    );
  }
}
