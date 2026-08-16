// lib/widgets/last_price_hint.dart
// Petit encart contextuel affichant le dernier prix d'un produit vendu à un client.

import 'package:flutter/material.dart';
import '../utils/formatters.dart';

class LastPriceHint extends StatelessWidget {
  /// Dernier prix unitaire connu (null = pas d'historique, on n'affiche rien).
  final double? lastPrice;

  /// Nom du client concerné (null ou vide = libellé générique).
  final String? clientName;

  const LastPriceHint({super.key, this.lastPrice, this.clientName});

  @override
  Widget build(BuildContext context) {
    final price = lastPrice;
    if (price == null) return const SizedBox.shrink();

    final client = (clientName ?? '').trim();
    final label = client.isEmpty
        ? 'Dernier prix connu : ${formatCurrency(price)}'
        : 'Dernier prix pour $client : ${formatCurrency(price)}';

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
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
