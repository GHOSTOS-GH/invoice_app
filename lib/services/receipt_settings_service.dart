// lib/services/receipt_settings_service.dart
// Persistance (SharedPreferences) des paramètres du reçu thermique.
// Expose un ValueNotifier global : toute modification met à jour
// l'aperçu du reçu en temps réel, où qu'il soit ouvert.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt_settings.dart';
import '../utils/constants.dart';

class ReceiptSettingsService {
  static const String _settingsKey = Constants.receiptSettingsKey;
  static const String _defaultPrinterKey = Constants.defaultPrinterMacKey;
  static const String _defaultPrinterIpKey = Constants.defaultPrinterIpKey;

  /// Notifié à chaque chargement / sauvegarde des paramètres du reçu.
  /// L'écran d'aperçu s'y abonne pour se rafraîchir en temps réel.
  static final ValueNotifier<ReceiptSettings> settingsNotifier =
      ValueNotifier<ReceiptSettings>(ReceiptSettings.defaults());

  // ---------- Paramètres du reçu ----------

  Future<ReceiptSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    ReceiptSettings settings;
    if (raw == null) {
      settings = ReceiptSettings.defaults();
    } else {
      try {
        settings =
            ReceiptSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Paramètres corrompus : on repart des valeurs par défaut.
        settings = ReceiptSettings.defaults();
      }
    }
    // N'écrit dans le notifier QUE si la valeur a réellement changé
    // (égalité par valeur de ReceiptSettings). Sans cette garde, chaque
    // chargement créerait une nouvelle instance jugée « différente » par
    // ValueNotifier → notifyListeners() → rechargement → boucle infinie
    // à l'ouverture de l'aperçu du reçu.
    // N'écrit dans le notifier QUE si la valeur a réellement changé
    // (égalité par valeur de ReceiptSettings). Sans cette garde, chaque
    // chargement créerait une nouvelle instance jugée « différente » par
    // ValueNotifier → notifyListeners() → rechargement → boucle infinie
    // à l'ouverture de l'aperçu du reçu.
    if (settingsNotifier.value != settings) {
      settingsNotifier.value = settings;
    }
    return settings;
  }

  Future<void> saveSettings(ReceiptSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    settingsNotifier.value = settings;
  }

  // ---------- Imprimante par défaut (adresse MAC) ----------

  Future<String?> getDefaultPrinterMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultPrinterKey);
  }

  Future<void> saveDefaultPrinterMac(String? mac) async {
    final prefs = await SharedPreferences.getInstance();
    if (mac == null) {
      await prefs.remove(_defaultPrinterKey);
    } else {
      await prefs.setString(_defaultPrinterKey, mac);
    }
  }

  // ---------- Imprimante Wi-Fi par défaut (adresse IP) ----------

  Future<String?> getDefaultPrinterIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultPrinterIpKey);
  }

  Future<void> saveDefaultPrinterIp(String? ip) async {
    final prefs = await SharedPreferences.getInstance();
    if (ip == null) {
      await prefs.remove(_defaultPrinterIpKey);
    } else {
      await prefs.setString(_defaultPrinterIpKey, ip.trim());
    }
  }
}
