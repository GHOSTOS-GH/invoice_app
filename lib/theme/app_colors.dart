// lib/theme/app_colors.dart
// Palette unique de l'application. Aucune couleur en dur ne doit exister
// ailleurs que dans lib/theme/.

import 'package:flutter/material.dart';

import '../models/invoice.dart';

/// Couleurs d'un statut : texte lisible sur son fond (contraste AA garanti).
@immutable
class StatusPalette {
  final Color foreground;
  final Color background;

  const StatusPalette({required this.foreground, required this.background});
}

/// Extension de thème exposant tous les jetons de couleur de l'application.
///
/// Les valeurs claires et sombres vivent ici : les écrans ne connaissent que
/// les noms des jetons (`AppColors.of(context).primary`, etc.).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color primary;
  final Color onPrimary;

  /// Variante foncée du primaire, utilisée pour les dégradés.
  final Color primaryStrong;

  /// Fond général des écrans (sous les cartes).
  final Color canvas;

  /// Fond des cartes, barres et feuilles.
  final Color surface;

  /// Fond alternatif discret (champs, encarts, puces inactives).
  final Color surfaceAlt;

  final Color border;
  final Color textStrong;
  final Color textBody;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color shadow;

  final StatusPalette statusEnCours;
  final StatusPalette statusEnLivraison;
  final StatusPalette statusLivree;
  final StatusPalette statusArchivee;

  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryStrong,
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textStrong,
    required this.textBody,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.shadow,
    required this.statusEnCours,
    required this.statusEnLivraison,
    required this.statusLivree,
    required this.statusArchivee,
  });

  /// Palette claire (contrastes ≥ AA sur fond blanc).
  static const AppColors light = AppColors(
    primary: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    primaryStrong: Color(0xFF1D4ED8),
    canvas: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    textStrong: Color(0xFF0F172A),
    textBody: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    danger: Color(0xFFB91C1C),
    info: Color(0xFF1D4ED8),
    shadow: Color(0x140F172A),
    statusEnCours: StatusPalette(
      foreground: Color(0xFF1D4ED8),
      background: Color(0xFFDBEAFE),
    ),
    statusEnLivraison: StatusPalette(
      foreground: Color(0xFF92400E),
      background: Color(0xFFFEF3C7),
    ),
    statusLivree: StatusPalette(
      foreground: Color(0xFF166534),
      background: Color(0xFFDCFCE7),
    ),
    statusArchivee: StatusPalette(
      foreground: Color(0xFF475569),
      background: Color(0xFFE2E8F0),
    ),
  );

  /// Palette sombre (textes clairs sur surfaces profondes).
  static const AppColors dark = AppColors(
    primary: Color(0xFF60A5FA),
    onPrimary: Color(0xFF0B1220),
    primaryStrong: Color(0xFF3B82F6),
    canvas: Color(0xFF0B1220),
    surface: Color(0xFF141C2B),
    surfaceAlt: Color(0xFF1E293B),
    border: Color(0xFF2A3646),
    textStrong: Color(0xFFF1F5F9),
    textBody: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF93C5FD),
    shadow: Color(0x66000000),
    statusEnCours: StatusPalette(
      foreground: Color(0xFFBFDBFE),
      background: Color(0xFF1E3A8A),
    ),
    statusEnLivraison: StatusPalette(
      foreground: Color(0xFFFDE68A),
      background: Color(0xFF78350F),
    ),
    statusLivree: StatusPalette(
      foreground: Color(0xFFBBF7D0),
      background: Color(0xFF14532D),
    ),
    statusArchivee: StatusPalette(
      foreground: Color(0xFFE2E8F0),
      background: Color(0xFF334155),
    ),
  );

  /// Jetons du thème courant (repli sur la palette claire hors MaterialApp).
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  StatusPalette statusOf(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.enCours:
        return statusEnCours;
      case InvoiceStatus.enLivraison:
        return statusEnLivraison;
      case InvoiceStatus.livree:
        return statusLivree;
      case InvoiceStatus.archivee:
        return statusArchivee;
    }
  }

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primaryStrong,
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textStrong,
    Color? textBody,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? shadow,
    StatusPalette? statusEnCours,
    StatusPalette? statusEnLivraison,
    StatusPalette? statusLivree,
    StatusPalette? statusArchivee,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      textStrong: textStrong ?? this.textStrong,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      shadow: shadow ?? this.shadow,
      statusEnCours: statusEnCours ?? this.statusEnCours,
      statusEnLivraison: statusEnLivraison ?? this.statusEnLivraison,
      statusLivree: statusLivree ?? this.statusLivree,
      statusArchivee: statusArchivee ?? this.statusArchivee,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    StatusPalette mixStatus(StatusPalette a, StatusPalette b) => StatusPalette(
          foreground: mix(a.foreground, b.foreground),
          background: mix(a.background, b.background),
        );
    return AppColors(
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      primaryStrong: mix(primaryStrong, other.primaryStrong),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      border: mix(border, other.border),
      textStrong: mix(textStrong, other.textStrong),
      textBody: mix(textBody, other.textBody),
      textMuted: mix(textMuted, other.textMuted),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
      shadow: mix(shadow, other.shadow),
      statusEnCours: mixStatus(statusEnCours, other.statusEnCours),
      statusEnLivraison:
          mixStatus(statusEnLivraison, other.statusEnLivraison),
      statusLivree: mixStatus(statusLivree, other.statusLivree),
      statusArchivee: mixStatus(statusArchivee, other.statusArchivee),
    );
  }
}

/// Couleurs du statut [status] pour le thème courant.
///
/// Remplace `InvoiceStatus.color` : le modèle ne porte plus aucune couleur,
/// et le PDF garde son propre mapping (étape 5).
StatusPalette statusStyle(BuildContext context, InvoiceStatus status) =>
    AppColors.of(context).statusOf(status);

/// Couleurs fixes du papier (aperçu du reçu) : un ticket reste blanc avec une
/// encre noire, quel que soit le thème de l'application.
abstract final class PaperColors {
  static const Color sheet = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF000000);
  static const Color rule = Color(0xFFE2E8F0);
  static const Color backdrop = Color(0xFFE2E8F0);
}
