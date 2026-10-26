// lib/services/document_settings_service.dart
// Persistance (SharedPreferences, clé `document_settings`) des réglages du
// document de facture. Expose un ValueNotifier global : l'aperçu se rafraîchit
// dès qu'un réglage change, et le générateur PDF/images lit toujours l'état
// courant.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_settings.dart';
import '../models/receipt_settings.dart';
import '../utils/constants.dart';
import 'receipt_settings_service.dart';

class DocumentSettingsService {
  DocumentSettingsService({
    Future<Directory> Function()? documentsDirectory,
    Future<ReceiptSettings> Function()? receiptSettingsLoader,
  })  : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _receiptSettingsLoader =
            receiptSettingsLoader ?? ReceiptSettingsService().loadSettings;

  /// Instance partagée par les écrans.
  static final DocumentSettingsService instance = DocumentSettingsService();

  static const String settingsKey = Constants.documentSettingsKey;

  /// Dossier des images du document (logo choisi par l'utilisateur).
  static const String assetsFolderName = 'doc_assets';

  /// Notifié à chaque chargement / enregistrement des réglages.
  static final ValueNotifier<DocumentSettings> settingsNotifier =
      ValueNotifier<DocumentSettings>(DocumentSettings.defaults());

  final Future<Directory> Function() _documentsDirectory;
  final Future<ReceiptSettings> Function() _receiptSettingsLoader;

  /// Charge les réglages. Clé absente : les informations déjà saisies pour le
  /// reçu thermique sont recopiées (une seule fois), sans jamais modifier
  /// ReceiptSettings. JSON corrompu : valeurs par défaut, sans crash.
  Future<DocumentSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(settingsKey);

    DocumentSettings settings;
    if (raw == null) {
      settings = await _seededFromReceipt();
      try {
        await prefs.setString(settingsKey, jsonEncode(settings.toJson()));
      } catch (error) {
        debugPrint('DocumentSettingsService : écriture impossible ($error)');
      }
    } else {
      settings = _decode(raw);
    }

    if (settingsNotifier.value != settings) {
      settingsNotifier.value = settings;
    }
    return settings;
  }

  DocumentSettings _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DocumentSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return DocumentSettings.fromJson(
          decoded.map((key, value) => MapEntry('$key', value)),
        );
      }
    } catch (error) {
      debugPrint('DocumentSettingsService : JSON illisible ($error)');
    }
    return DocumentSettings.defaults();
  }

  /// Valeurs par défaut, complétées par ce qui existe déjà dans les réglages
  /// du reçu thermique (nom, adresse, téléphone, NINEA / RC).
  Future<DocumentSettings> _seededFromReceipt() async {
    const defaults = DocumentSettings();
    ReceiptSettings receipt;
    try {
      receipt = await _receiptSettingsLoader();
    } catch (error) {
      debugPrint('DocumentSettingsService : reçu illisible ($error)');
      return defaults;
    }
    return defaults.copyWith(
      businessName: _or(receipt.shopName, defaults.businessName),
      businessAddress: _or(receipt.shopAddress, defaults.businessAddress),
      businessPhone: _or(receipt.shopPhone, defaults.businessPhone),
      businessRegistration:
          _or(receipt.shopNinea, defaults.businessRegistration),
    );
  }

  static String _or(String value, String fallback) =>
      value.trim().isEmpty ? fallback : value.trim();

  Future<void> saveSettings(DocumentSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(settingsKey, jsonEncode(settings.toJson()));
    if (settingsNotifier.value != settings) {
      settingsNotifier.value = settings;
    }
  }

  /// Rétablit tous les réglages par défaut.
  Future<DocumentSettings> resetToDefaults() async {
    const defaults = DocumentSettings();
    await saveSettings(defaults);
    return defaults;
  }

  /// Recopie les informations d'entreprise du reçu thermique dans le document.
  /// Le reçu lui-même n'est jamais modifié.
  Future<DocumentSettings> copyBusinessInfoFromReceipt() async {
    final receipt = await _receiptSettingsLoader();
    final current = settingsNotifier.value;
    final next = current.copyWith(
      businessName: _or(receipt.shopName, current.businessName),
      businessAddress: _or(receipt.shopAddress, current.businessAddress),
      businessPhone: _or(receipt.shopPhone, current.businessPhone),
      businessRegistration:
          _or(receipt.shopNinea, current.businessRegistration),
    );
    await saveSettings(next);
    return next;
  }

  /// Copie le logo choisi dans `documents/doc_assets` et renvoie son chemin.
  Future<String> importLogo(String sourcePath) async {
    final source = File(sourcePath);
    final documents = await _documentsDirectory();
    final dir = Directory(
      '${documents.path}${Platform.pathSeparator}$assetsFolderName',
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final extension = _extensionOf(sourcePath);
    final name = 'logo_${DateTime.now().millisecondsSinceEpoch}$extension';
    final destination = File('${dir.path}${Platform.pathSeparator}$name');
    await source.copy(destination.path);
    return destination.path;
  }

  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.png';
    final extension = name.substring(dot).toLowerCase();
    return extension.length > 6 ? '.png' : extension;
  }
}
