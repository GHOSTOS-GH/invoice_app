// lib/services/pdf/pdf_palette.dart
// Couleurs du document PDF : palette dédiée au PDF, indépendante du thème de
// l'application (un document imprimé reste clair), mais cohérente avec les
// jetons de `lib/theme/app_colors.dart`.
//
// Aucun dégradé ni ombre floue : uniquement des aplats (rapides à rasteriser
// et à imprimer).

import 'package:pdf/pdf.dart';

import '../../models/invoice.dart';

/// Couleurs d'un statut dans le PDF (mêmes valeurs que `AppColors.light`).
class PdfStatusColors {
  final PdfColor foreground;
  final PdfColor background;

  const PdfStatusColors({required this.foreground, required this.background});
}

/// Palette du document, dérivée de la couleur d'accent choisie.
class PdfPalette {
  /// Accent principal (aplats, filets, montants).
  final PdfColor accent;

  /// Accent assombri (titres, montant total).
  final PdfColor accentStrong;

  /// Aplat très clair dérivé de l'accent (lignes alternées, encarts).
  final PdfColor accentSoft;

  /// Encre principale.
  final PdfColor ink;

  /// Texte courant.
  final PdfColor body;

  /// Texte secondaire (libellés, mentions).
  final PdfColor muted;

  /// Filets et bordures.
  final PdfColor border;

  /// Fond très clair des encarts neutres.
  final PdfColor surfaceAlt;

  final PdfColor white;

  const PdfPalette({
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.ink,
    required this.body,
    required this.muted,
    required this.border,
    required this.surfaceAlt,
    required this.white,
  });

  /// Palette construite à partir de la couleur d'accent ARGB du document.
  factory PdfPalette.fromAccent(int accentArgb) {
    final accent = PdfColor.fromInt(accentArgb | 0xFF000000);
    return PdfPalette(
      accent: accent,
      accentStrong: mix(accent, const PdfColor.fromInt(0xFF000000), 0.22),
      accentSoft: mix(accent, const PdfColor.fromInt(0xFFFFFFFF), 0.94),
      ink: const PdfColor.fromInt(0xFF0F172A),
      body: const PdfColor.fromInt(0xFF475569),
      muted: const PdfColor.fromInt(0xFF64748B),
      border: const PdfColor.fromInt(0xFFE2E8F0),
      surfaceAlt: const PdfColor.fromInt(0xFFF1F5F9),
      white: const PdfColor.fromInt(0xFFFFFFFF),
    );
  }

  /// Mélange [a] vers [b] : [t] = 0 → [a], 1 → [b].
  static PdfColor mix(PdfColor a, PdfColor b, double t) {
    final clamped = t.clamp(0.0, 1.0);
    return PdfColor(
      a.red + (b.red - a.red) * clamped,
      a.green + (b.green - a.green) * clamped,
      a.blue + (b.blue - a.blue) * clamped,
      a.alpha + (b.alpha - a.alpha) * clamped,
    );
  }

  /// Couleurs du badge de statut, cohérentes avec l'application.
  static PdfStatusColors statusColors(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.enCours:
        return const PdfStatusColors(
          foreground: PdfColor.fromInt(0xFF1D4ED8),
          background: PdfColor.fromInt(0xFFDBEAFE),
        );
      case InvoiceStatus.enLivraison:
        return const PdfStatusColors(
          foreground: PdfColor.fromInt(0xFF92400E),
          background: PdfColor.fromInt(0xFFFEF3C7),
        );
      case InvoiceStatus.livree:
        return const PdfStatusColors(
          foreground: PdfColor.fromInt(0xFF166534),
          background: PdfColor.fromInt(0xFFDCFCE7),
        );
      case InvoiceStatus.archivee:
        return const PdfStatusColors(
          foreground: PdfColor.fromInt(0xFF475569),
          background: PdfColor.fromInt(0xFFE2E8F0),
        );
    }
  }
}
