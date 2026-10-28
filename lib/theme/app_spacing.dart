// lib/theme/app_spacing.dart
// Grille d'espacement 4 / 8 de l'application.

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Retrait horizontal standard des écrans.
  static const double screen = lg;
}

/// Zone tactile minimale recommandée par les règles du projet.
const double kMinTapTarget = 48;
