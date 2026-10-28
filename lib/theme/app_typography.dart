// lib/theme/app_typography.dart
// Échelle typographique de l'application (police Inter embarquée).
//
// Aucune taille n'est inférieure à 12 sp : les tests de qualité visuelle
// vérifient ce plancher avec un textScaler à 1.3.

import 'package:flutter/material.dart';

abstract final class AppFont {
  static const String family = 'Inter';
}

abstract final class AppTypography {
  static const TextTheme textTheme = TextTheme(
    displaySmall: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      height: 1.15,
    ),
    headlineMedium: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    headlineSmall: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.25,
    ),
    titleLarge: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.3,
    ),
    titleSmall: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyLarge: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    bodySmall: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    labelLarge: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelSmall: TextStyle(
      fontFamily: AppFont.family,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      height: 1.2,
    ),
  );
}
