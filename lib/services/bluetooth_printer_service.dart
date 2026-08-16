// lib/services/bluetooth_printer_service.dart
// Gestion de l'imprimante thermique Bluetooth (Android uniquement).
// Découverte (appareils appairés), connexion, mémorisation de
// l'imprimante par défaut et impression d'une facture.

import 'dart:io';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:permission_handler/permission_handler.dart';

import '../models/invoice.dart';
import '../models/receipt_settings.dart';
import 'receipt_printer_common.dart';
import 'receipt_settings_service.dart';

/// Taille d'un chunk d'envoi ESC/POS (en octets). Les modules Bluetooth à
/// petit buffer perdent des données si tout le flux est envoyé d'un bloc —
/// particulièrement critique pour le logo rastérisé.
const int kBluetoothChunkSize = 512;

/// Délai entre deux chunks : laisse le temps à l'imprimante d'absorber
/// les octets reçus avant d'en envoyer de nouveaux.
const Duration kBluetoothChunkDelay = Duration(milliseconds: 25);

/// Délai maximal d'attente d'une écriture avant de considérer que
/// l'imprimante ne répond plus.
const Duration kBluetoothWriteTimeout = Duration(seconds: 15);

/// Court délai après connect() avant de revérifier isConnected : filet de
/// sécurité quand le plugin renvoie un faux « non connecté » alors que le
/// socket est en réalité ouvert.
const Duration kBluetoothConnectSettleDelay = Duration(milliseconds: 300);

/// Résultat d'une tentative de connexion : [connected] indique si le
/// socket est ouvert, [alreadyConnected] si le plugin a rejeté la
/// tentative car un socket résiduel était encore ouvert.
typedef BluetoothConnectAttempt = ({bool connected, bool alreadyConnected});

/// Permission Bluetooth refusée (Android 12+ : BLUETOOTH_SCAN /
/// BLUETOOTH_CONNECT). Message actionnable invitant à activer la
/// permission dans les réglages de l'application.
class BluetoothPermissionDeniedException implements Exception {
  final String message;
  const BluetoothPermissionDeniedException(this.message);

  @override
  String toString() => message;
}

/// Bluetooth indisponible : adaptateur absent, Bluetooth éteint,
/// accès au matériel impossible, etc.
class BluetoothUnavailableException implements Exception {
  final String message;
  const BluetoothUnavailableException(this.message);

  @override
  String toString() => message;
}

class BluetoothPrinterService {
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;
  final ReceiptSettingsService _settingsService = ReceiptSettingsService();

  /// L'impression Bluetooth n'est disponible que sur Android.
  bool get isSupported => Platform.isAndroid;

  // ---------- Permissions runtime (Android 12+) ----------

  /// Demande explicitement les permissions runtime Bluetooth
  /// (BLUETOOTH_SCAN puis BLUETOOTH_CONNECT) avant tout accès au
  /// matériel. Sur Android < 12, permission_handler ne les ajoute pas
  /// (retour « accordé » automatique), donc l'appel est sans effet.
  ///
  /// Lance une [BluetoothPermissionDeniedException] avec un message
  /// actionnable si l'une des permissions est refusée.
  Future<bool> ensureBluetoothPermissions() async {
    if (!Platform.isAndroid) return false;

    final scan = await Permission.bluetoothScan.request();
    if (!scan.isGranted) {
      throw const BluetoothPermissionDeniedException(
        "Permission Bluetooth refusée. Autorisez l'accès aux « Appareils à "
        "proximité » pour cette application dans les réglages Android, puis "
        "réessayez.",
      );
    }

    final connect = await Permission.bluetoothConnect.request();
    if (!connect.isGranted) {
      throw const BluetoothPermissionDeniedException(
        "Permission Bluetooth refusée. Autorisez l'accès aux « Appareils à "
        "proximité » dans les réglages de l'application, puis réessayez.",
      );
    }
    return true;
  }

  /// Ouvre les réglages de l'application (pour activer les permissions).
  Future<void> openAppSettingsPage() => openAppSettings();

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

  /// Connexion directe (bas niveau). Le plugin natif répond `true`
  /// (bool) quand la connexion est établie ; les échecs remontent en
  /// PlatformException (« connect_error »…).
  Future<bool> connect(BluetoothDevice device) async =>
      (await _printer.connect(device)) == true;

  Future<void> disconnect() => _printer.disconnect();

  /// Déconnexion « best effort » : ignore l'erreur native « not
  /// connected » (socket déjà fermé). Utilisée avant toute reconnexion.
  Future<void> _disconnectQuietly() async {
    try {
      await disconnect();
    } on PlatformException catch (e) {
      if (e.code == 'disconnection_error' &&
          (e.message ?? '').toLowerCase().contains('not connected')) {
        return; // déjà déconnecté : rien à faire.
      }
      rethrow;
    }
  }

  /// Tente une connexion directe à [device] en absorbant l'erreur native
  /// « already connected » (socket résiduel) : dans ce cas, déconnecte et
  /// retourne (connected: false, alreadyConnected: true) pour que
  /// connectSafely() puisse réessayer. Les autres erreurs sont propagées
  /// telles quelles (permissions, appareil introuvable…).
  ///
  /// Après une connexion établie, attend un court délai puis revérifie
  /// isConnected : le plugin renvoie parfois un faux « non connecté »
  /// juste après connect() alors que le socket est en réalité ouvert.
  Future<BluetoothConnectAttempt> _attemptConnect(
      BluetoothDevice device) async {
    bool connected;
    var alreadyConnected = false;
    try {
      connected = await connect(device);
    } on PlatformException catch (e) {
      if (e.code == 'connect_error' &&
          (e.message ?? '').toLowerCase().contains('already connected')) {
        // Socket résiduel non fermé : on le libère, connectSafely()
        // réessaiera automatiquement une fois.
        alreadyConnected = true;
        connected = false;
      } else {
        rethrow;
      }
    }
    if (!connected) {
      return (connected: false, alreadyConnected: alreadyConnected);
    }

    // Filet de sécurité : laisse le socket se stabiliser puis revérifie
    // avant de décider si la connexion est réellement établie.
    await Future<void>.delayed(kBluetoothConnectSettleDelay);
    final stillConnected = await isConnected;
    return (connected: stillConnected, alreadyConnected: false);
  }

  /// Connexion robuste à [device], réutilisée par la feuille de sélection
  /// de l'imprimante et par imprimerFacture().
  ///
  /// 1. Si un socket existe déjà (isConnected), le ferme d'abord via
  ///    disconnect() pour éviter l'erreur native « already connected »
  ///    quand un socket précédent n'a pas été proprement fermé.
  /// 2. Tente connect(device) ; si le plugin signale « already connected »,
  ///    déconnecte puis réessaie automatiquement une fois.
  /// 3. Après connect(), attend un court délai puis revérifie isConnected
  ///    avant de conclure (faux « non connecté » possible du plugin).
  ///
  /// Retourne true si le socket est ouvert, false sinon.
  Future<bool> connectSafely(BluetoothDevice device) async {
    // 1. Déconnexion préalable si un socket existe déjà.
    if (await isConnected) {
      await _disconnectQuietly();
    }

    // 2. Première tentative.
    var attempt = await _attemptConnect(device);
    if (!attempt.connected && attempt.alreadyConnected) {
      // Socket résiduel libéré : réessaie une fois automatiquement.
      await _disconnectQuietly();
      attempt = await _attemptConnect(device);
    }
    return attempt.connected;
  }

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
  /// Lance une exception avec un message explicite si :
  ///  - la permission Bluetooth est refusée ([BluetoothPermissionDeniedException]),
  ///  - le Bluetooth est indisponible ou éteint ([BluetoothUnavailableException]),
  ///  - aucune imprimante par défaut n'est enregistrée,
  ///  - l'imprimante n'est plus appairée,
  ///  - la connexion échoue ou l'imprimante ne répond pas dans les 15 s.
  Future<void> imprimerFacture(Invoice invoice,
      {ReceiptSettings? settings}) async {
    if (!isSupported) {
      throw StateError(
          "L'impression Bluetooth est disponible uniquement sur Android.");
    }

    // Permissions runtime avant tout accès au matériel Bluetooth.
    await ensureBluetoothPermissions();

    // Prépare le contenu du reçu (logo inclus si présent).
    final (_, bytes) = await prepareReceiptBytes(invoice, settings: settings);

    // Résout l'imprimante par défaut.
    final mac = await getDefaultPrinterMac();
    if (mac == null) {
      throw StateError(
          "Aucune imprimante par défaut. Ouvrez l'aperçu du reçu puis choisissez une imprimante.");
    }

    // Vérifie que le Bluetooth est bien activé avant d'aller plus loin.
    try {
      final on = await isOn;
      if (!on) {
        throw const BluetoothUnavailableException(
            "Le Bluetooth est désactivé. Activez-le puis réessayez.");
      }
    } on BluetoothUnavailableException {
      rethrow;
    } catch (_) {
      // Impossible de lire l'état : on laisse la connexion trancher.
    }

    // Retrouve l'appareil appairé correspondant à l'adresse MAC mémorisée.
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
      throw const BluetoothUnavailableException(
          "Impossible d'accéder au Bluetooth. Vérifiez qu'il est activé et réessayez.");
    }
    if (device == null) {
      throw StateError(
          "Imprimante par défaut introuvable. Réappairez-la ou choisissez-en une autre.");
    }

    try {
      // Connexion robuste (déconnexion préalable si nécessaire, gestion
      // du socket résiduel « already connected », re-vérification après
      // un court délai), puis envoi des données.
      final ok = await connectSafely(device);
      if (!ok) {
        throw StateError(
            "Connexion à « ${device.name ?? mac} » impossible. Vérifiez que l'imprimante est allumée et à proximité.");
      }

      // Envoi par chunks de 512 octets avec une courte pause entre chaque :
      // évite la perte de données sur les modules Bluetooth à petit buffer.
      // Chaque écriture est bornée par un timeout de 15 secondes.
      final data = Uint8List.fromList(bytes);
      for (var i = 0; i < data.length; i += kBluetoothChunkSize) {
        final end = (i + kBluetoothChunkSize < data.length)
            ? i + kBluetoothChunkSize
            : data.length;
        await _printer.writeBytes(data.sublist(i, end)).timeout(
              kBluetoothWriteTimeout,
              onTimeout: () =>
                  throw StateError("L'imprimante ne répond pas, réessayez."),
            );
        if (i + kBluetoothChunkSize < data.length) {
          await Future<void>.delayed(kBluetoothChunkDelay);
        }
      }
    } finally {
      // Libère la connexion Bluetooth entre deux impressions, en cas de
      // succès comme d'échec.
      try {
        await _printer.disconnect();
      } catch (_) {
        // Déconnexion « best effort » : l'imprimante peut déjà être déconnectée.
      }
    }
  }
}
