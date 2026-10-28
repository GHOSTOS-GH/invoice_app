// lib/widgets/ui/app_snack.dart

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

enum SnackTone { neutral, success, error, info }

/// Point d'entrée unique des snackbars de l'application : mêmes formes,
/// mêmes couleurs de thème, contraste garanti dans les deux modes.
abstract final class AppSnack {
  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) =>
      show(
        context,
        message,
        tone: SnackTone.success,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) =>
      show(
        context,
        message,
        tone: SnackTone.error,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) =>
      show(
        context,
        message,
        tone: SnackTone.info,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void neutral(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) =>
      show(
        context,
        message,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void show(
    BuildContext context,
    String message, {
    SnackTone tone = SnackTone.neutral,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color background = switch (tone) {
      SnackTone.success => colors.success,
      SnackTone.error => colors.danger,
      SnackTone.info => colors.info,
      SnackTone.neutral => colors.textStrong,
    };
    final Color foreground = isDark ? colors.canvas : colors.surface;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: foreground,
                  onPressed: onAction ?? () {},
                ),
        ),
      );
  }
}
