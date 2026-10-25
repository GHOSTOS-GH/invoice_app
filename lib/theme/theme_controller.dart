// lib/theme/theme_controller.dart
// Choix du thème (Système / Clair / Sombre) persisté dans SharedPreferences
// sous la clé « theme_mode ».

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);

  static final ThemeController instance = ThemeController._();

  /// Clé de persistance : ne jamais la renommer.
  static const String storageKey = 'theme_mode';

  static const Map<ThemeMode, String> _values = {
    ThemeMode.system: 'system',
    ThemeMode.light: 'light',
    ThemeMode.dark: 'dark',
  };

  /// Charge le choix enregistré ; « Système » par défaut.
  Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(storageKey);
    final mode = _values.entries
        .firstWhere(
          (entry) => entry.value == stored,
          orElse: () => const MapEntry(ThemeMode.system, 'system'),
        )
        .key;
    value = mode;
    return mode;
  }

  /// Enregistre puis applique le mode choisi.
  Future<void> setMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, _values[mode] ?? 'system');
    value = mode;
  }

  /// Libellé français du mode.
  static String labelOf(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Système';
      case ThemeMode.light:
        return 'Clair';
      case ThemeMode.dark:
        return 'Sombre';
    }
  }
}
