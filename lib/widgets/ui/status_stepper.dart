// lib/widgets/ui/status_stepper.dart

import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'status_badge.dart';

/// Progression du statut : En cours → En livraison → Livrée.
///
/// L'archivage est présenté à part. En lecture seule ([onChanged] null),
/// aucun élément n'est interactif ; en édition, chaque étape est sélectionnable.
class StatusStepper extends StatelessWidget {
  final InvoiceStatus status;
  final ValueChanged<InvoiceStatus>? onChanged;

  const StatusStepper({super.key, required this.status, this.onChanged});

  static const List<InvoiceStatus> _steps = [
    InvoiceStatus.enCours,
    InvoiceStatus.enLivraison,
    InvoiceStatus.livree,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isArchived = status == InvoiceStatus.archivee;
    final currentIndex = _steps.indexOf(status);
    final interactive = onChanged != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0)
                SizedBox(
                  width: 12,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Container(
                      height: 2,
                      color: !isArchived && currentIndex >= i
                          ? colors.primary
                          : colors.border,
                    ),
                  ),
                ),
              Expanded(
                child: _Step(
                  label: _steps[i].label,
                  index: i,
                  isDone: !isArchived && currentIndex >= i,
                  isCurrent: !isArchived && currentIndex == i,
                  onTap: interactive ? () => onChanged!(_steps[i]) : null,
                  colors: colors,
                  textTheme: textTheme,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _ArchiveRow(
          status: status,
          isArchived: isArchived,
          onTap: interactive ? () => onChanged!(InvoiceStatus.archivee) : null,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String label;
  final int index;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback? onTap;
  final AppColors colors;
  final TextTheme textTheme;

  const _Step({
    required this.label,
    required this.index,
    required this.isDone,
    required this.isCurrent,
    required this.onTap,
    required this.colors,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDone ? colors.primary : colors.surfaceAlt,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDone ? colors.primary : colors.border,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: isDone
          ? Icon(Icons.check, size: 16, color: colors.onPrimary)
          : Text(
              '${index + 1}',
              style: textTheme.labelSmall?.copyWith(
                color: colors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: isDone ? colors.textStrong : colors.textMuted,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );

    final sized = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinTapTarget),
      child: child,
    );

    return onTap == null
        ? sized
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: sized,
            ),
          );
  }
}

class _ArchiveRow extends StatelessWidget {
  final InvoiceStatus status;
  final bool isArchived;
  final VoidCallback? onTap;

  const _ArchiveRow({
    required this.status,
    required this.isArchived,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final content = Container(
      constraints: const BoxConstraints(minHeight: kMinTapTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isArchived ? colors.statusArchivee.background : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isArchived ? colors.statusArchivee.foreground : colors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isArchived ? Icons.inventory_2 : Icons.archive_outlined,
            size: 18,
            color: isArchived
                ? colors.statusArchivee.foreground
                : colors.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isArchived ? 'Facture archivée' : 'Archiver la facture',
              style: textTheme.bodyMedium?.copyWith(
                color: isArchived
                    ? colors.statusArchivee.foreground
                    : colors.textBody,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isArchived) StatusBadge(status: status, compact: true),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}
