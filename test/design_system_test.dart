// test/design_system_test.dart
// Fondations visuelles : contrastes AA des jetons, statuts distincts et
// ThemeController persistant.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/theme/app_colors.dart';
import 'package:invoice_app/theme/app_radius.dart';
import 'package:invoice_app/theme/app_spacing.dart';
import 'package:invoice_app/theme/theme_controller.dart';

/// Luminance relative WCAG d'une couleur (canaux 0 → 1).
double _luminance(Color color) {
  double linear(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

/// Contraste WCAG entre deux couleurs (1 → 21).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppColors : contrastes AA', () {
    void expectAa(String label, Color foreground, Color background,
        {double minimum = 4.5}) {
      final ratio = _contrast(foreground, background);
      expect(
        ratio,
        greaterThanOrEqualTo(minimum),
        reason: '$label : contraste ${ratio.toStringAsFixed(2)} < $minimum',
      );
    }

    test('palette claire', () {
      const c = AppColors.light;
      expectAa('textStrong / surface', c.textStrong, c.surface);
      expectAa('textBody / surface', c.textBody, c.surface);
      expectAa('textMuted / surface', c.textMuted, c.surface);
      expectAa('onPrimary / primary', c.onPrimary, c.primary);
      expectAa('success / surface', c.success, c.surface);
      expectAa('warning / surface', c.warning, c.surface);
      expectAa('danger / surface', c.danger, c.surface);
      expectAa('info / surface', c.info, c.surface);
      for (final status in InvoiceStatus.values) {
        final palette = c.statusOf(status);
        expectAa(
          'statut ${status.label}',
          palette.foreground,
          palette.background,
        );
      }
    });

    test('palette sombre', () {
      const c = AppColors.dark;
      expectAa('textStrong / surface', c.textStrong, c.surface);
      expectAa('textBody / surface', c.textBody, c.surface);
      expectAa('textMuted / surface', c.textMuted, c.surface);
      expectAa('onPrimary / primary', c.onPrimary, c.primary);
      expectAa('success / surface', c.success, c.surface);
      expectAa('warning / surface', c.warning, c.surface);
      expectAa('danger / surface', c.danger, c.surface);
      expectAa('info / surface', c.info, c.surface);
      for (final status in InvoiceStatus.values) {
        final palette = c.statusOf(status);
        expectAa(
          'statut ${status.label}',
          palette.foreground,
          palette.background,
        );
      }
    });

    test('les 4 statuts sont nettement distincts', () {
      for (final colors in [AppColors.light, AppColors.dark]) {
        final foregrounds = InvoiceStatus.values
            .map((status) => colors.statusOf(status).foreground)
            .toSet();
        final backgrounds = InvoiceStatus.values
            .map((status) => colors.statusOf(status).background)
            .toSet();
        expect(foregrounds.length, 4);
        expect(backgrounds.length, 4);
      }
    });

    test('le statut « En cours » n\'est plus brun', () {
      final palette = AppColors.light.statusOf(InvoiceStatus.enCours);
      // Composante rouge et verte proches → teinte bleue, pas brune.
      expect(
          (palette.foreground.b - palette.foreground.r).abs(), greaterThan(0));
      expect(palette.foreground.b, greaterThan(palette.foreground.r));
    });
  });

  group('Grille et rayons', () {
    test('espacements 4/8', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 24);
      expect(AppSpacing.xxl, 32);
    });

    test('rayons', () {
      expect(AppRadius.sm, 10);
      expect(AppRadius.md, 14);
      expect(AppRadius.lg, 20);
    });
  });

  group('ThemeController', () {
    test('charge, persiste et relit le mode choisi', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController.instance;
      expect(await controller.load(), ThemeMode.system);

      await controller.setMode(ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeController.storageKey), 'dark');

      await controller.setMode(ThemeMode.light);
      expect(prefs.getString(ThemeController.storageKey), 'light');
      expect(await controller.load(), ThemeMode.light);
    });

    test('libellés français', () {
      expect(ThemeController.labelOf(ThemeMode.system), 'Système');
      expect(ThemeController.labelOf(ThemeMode.light), 'Clair');
      expect(ThemeController.labelOf(ThemeMode.dark), 'Sombre');
    });
  });
}
