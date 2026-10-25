// lib/widgets/last_price_hint.dart
// Petit encart contextuel affichant le dernier prix d'un produit vendu à un client.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';

class LastPriceHint extends StatelessWidget {
  /// Dernier prix unitaire connu (null = pas d'historique, on n'affiche rien).
  final int? lastPrice;

  /// Nom du client concerné (null ou vide = libellé générique).
  final String? clientName;

  /// Date de la vente d'origine (affiche « le 12/10/2026 » quand elle est
  /// connue).
  final DateTime? lastDate;

  /// Applique le dernier prix au champ de saisie (bouton « Utiliser ce prix »).
  final VoidCallback? onUsePrice;

  const LastPriceHint({
    super.key,
    this.lastPrice,
    this.clientName,
    this.lastDate,
    this.onUsePrice,
  });

  @override
  Widget build(BuildContext context) {
    final price = lastPrice;
    if (price == null) return const SizedBox.shrink();

    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final client = (clientName ?? '').trim();
    final label = client.isEmpty
        ? 'Dernier prix connu : ${formatCurrency(price)}'
        : 'Dernier prix pour $client : ${formatCurrency(price)}';
    final date = lastDate;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.info.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 17, color: colors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (date != null)
                  Text(
                    'le ${DateFormat('dd/MM/yyyy', 'fr_FR').format(date)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.info,
                    ),
                  ),
              ],
            ),
          ),
          if (onUsePrice != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onUsePrice,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Utiliser ce prix',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
