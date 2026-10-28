// lib/widgets/ui/app_card.dart

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Carte de surface standard : fond du thème, bordure discrète, coins arrondis.
///
/// Le fond est porté par un [Material] : les [ListTile] et effets d'encre
/// qu'elle contient peignent ainsi correctement leur fond et leurs ondulations.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final BorderSide? border;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.color,
    this.border,
    this.radius = AppRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final content = Padding(padding: padding, child: child);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ?? BorderSide(color: colors.border),
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? colors.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                splashColor: colors.primary.withValues(alpha: 0.06),
                highlightColor: colors.primary.withValues(alpha: 0.04),
                child: content,
              ),
      ),
    );
  }
}
