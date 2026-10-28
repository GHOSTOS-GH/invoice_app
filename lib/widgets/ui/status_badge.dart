// lib/widgets/ui/status_badge.dart

import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../theme/app_colors.dart';

/// Pastille de statut : fond teinté, texte contrasté (AA), compteur optionnel.
class StatusBadge extends StatelessWidget {
  final InvoiceStatus status;
  final int? count;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.count,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = statusStyle(context, status);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: palette.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: palette.foreground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  color: palette.background,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
