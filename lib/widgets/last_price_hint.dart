// lib/widgets/last_price_hint.dart
// Petit encart contextuel affichant le dernier prix d'un produit vendu à un client.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

    final client = (clientName ?? '').trim();
    final label = client.isEmpty
        ? 'Dernier prix connu : ${formatCurrency(price)}'
        : 'Dernier prix pour $client : ${formatCurrency(price)}';
    final date = lastDate;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 17, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
                if (date != null)
                  Text(
                    'le ${DateFormat('dd/MM/yyyy', 'fr_FR').format(date)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
              ],
            ),
          ),
          if (onUsePrice != null) ...[
            const SizedBox(width: 8),
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
