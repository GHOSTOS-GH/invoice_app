// lib/services/bluetooth_printer_service.dart
// Gestion de l'imprimante thermique Bluetooth (Android uniquement).
// Découverte (appareils appairés), connexion, mémorisation de
// l'imprimante par défaut et impression d'une facture.

import 'dart:io';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';

import '../models/invoice.dart';
import '../models/receipt_settings.dart';
import 'receipt_printer_common.dart';
import 'receipt_settings_service.dart';

class BluetoothPrinterService {
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;
  final ReceiptSettingsService _settingsService = ReceiptSettingsService();

  /// L'impression Bluetooth n'est disponible que sur Android.
  bool get isSupported => Platform.isAndroid;

  // ---------- État Bluetooth ----------

  Future<bool> get isAvailable async => (await _printer.isAvailable) ?? false;

  Future<bool> get isOn async => (await _printer.isOn) ?? false;

  Future<bool> get isConnected async => (await _printer.isConnected) ?? false;

  /// Liste des imprimantes / appareils Bluetooth déjà appairés.
  Future<List<BluetoothDevice>> getBondedDevices() =>
      _printer.getBondedDevices();

  /// Ouvre les réglages Bluetooth d'Android (pour appairer l'imprimante).
  Future<void> openBluetoothSettings() => _printer.openSettings;

  // ---------- Connexion ----------

  Future<bool> connect(BluetoothDevice device) async =>
      (await _printer.connect(device)) == BlueThermalPrinter.CONNECTED;

  Future<void> disconnect() => _printer.disconnect();

  // ---------- Imprimante par défaut ----------

  Future<String?> getDefaultPrinterMac() =>
      _settingsService.getDefaultPrinterMac();

  Future<void> saveDefaultPrinter(BluetoothDevice device) =>
      _settingsService.saveDefaultPrinterMac(device.address);

  Future<void> clearDefaultPrinter() =>
      _settingsService.saveDefaultPrinterMac(null);

  /// Retrouve l'appareil appairé correspondant à l'adresse MAC enregistrée.
  Future<BluetoothDevice?> getDefaultDevice() async {
    final mac = await getDefaultPrinterMac();
    if (mac == null) return null;
    final devices = await getBondedDevices();
    for (final d in devices) {
      if (d.address == mac) return d;
    }
    return null;
  }

  // ---------- Impression ----------

  /// Méthode réutilisable : génère le reçu ESC/POS de [invoice] et
  /// l'envoie à l'imprimante Bluetooth par défaut.
  ///
  /// Lance une [StateError] avec un message explicite si :
  ///  - aucune imprimante par défaut n'est enregistrée,
  ///  - l'imprimante n'est plus appairée,
  ///  - la connexion échoue.
  Future<void> imprimerFacture(Invoice invoice,
      {ReceiptSettings? settings}) async {
    if (!isSupported) {
      throw StateError(
          "L'impression Bluetooth est disponible uniquement sur Android.");
    }

    // Prépare le contenu du reçu (logo inclus si présent).
    final (_, bytes) = await prepareReceiptBytes(invoice, settings: settings);

    // Résout l'imprimante par défaut.
    final mac = await getDefaultPrinterMac();
    if (mac == null) {
      throw StateError(
          "Aucune imprimante par défaut. Ouvrez l'aperçu du reçu puis choisissez une imprimante.");
    }
    BluetoothDevice? device;
    try {
      final devices = await getBondedDevices();
      for (final d in devices) {
        if (d.address == mac) {
          device = d;
          break;
        }
      }
    } catch (_) {
      // Bluetooth indisponible (ex : émulateur) — message générique.
      throw StateError(
          "Impossible d'accéder au Bluetooth. Vérifiez qu'il est activé.");
    }
    if (device == null) {
      throw StateError(
          "Imprimante par défaut introuvable. Réappairez-la ou choisissez-en une autre.");
    }

    // Connexion si nécessaire, puis envoi des données.
    final connected = await isConnected;
    if (!connected) {
      final ok = await connect(device);
      if (!ok) {
        throw StateError(
            "Connexion à « ${device.name ?? mac} » impossible. Vérifiez que l'imprimante est allumée et à proximité.");
      }
    }

    await _printer.writeBytes(Uint8List.fromList(bytes));
  }
}
