// lib/services/network_printer_service.dart
// Impression Wi-Fi ESC/POS : envoi du reçu à l'imprimante thermique
// via un socket TCP (port 9100 par défaut).
// Fonctionne sur Android, iOS, macOS, Windows et Linux — contrairement
// au Bluetooth qui est limité à Android.

import 'dart:io';
import 'dart:typed_data';

import '../models/invoice.dart';
import '../models/receipt_settings.dart';
import 'receipt_printer_common.dart';
import 'receipt_settings_service.dart';

/// Port TCP standard des imprimantes ESC/POS.
const int kEscPosPort = 9100;

class NetworkPrinterService {
  final ReceiptSettingsService _settingsService = ReceiptSettingsService();

  Future<String?> getDefaultPrinterIp() =>
      _settingsService.getDefaultPrinterIp();

  Future<void> saveDefaultPrinterIp(String? ip) =>
      _settingsService.saveDefaultPrinterIp(ip);

  Future<void> clearDefaultPrinter() =>
      _settingsService.saveDefaultPrinterIp(null);

  /// Vérifie qu'une imprimante ESC/POS répond à [ip] sur le port 9100.
  /// Retourne un message d'erreur lisible, ou null si la connexion réussit.
  Future<String?> testConnection(String ip, {int port = kEscPosPort}) async {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 8));
      await socket.close();
      return null;
    } on SocketException catch (e) {
      return 'Connexion impossible : ${e.message}';
    } catch (e) {
      return 'Erreur : $e';
    }
  }

  /// Méthode réutilisable : génère le reçu ESC/POS de [invoice] et
  /// l'envoie à l'imprimante Wi-Fi par défaut (IP mémorisée).
  ///
  /// Lance une [StateError] avec un message explicite si aucune
  /// imprimante Wi-Fi n'est enregistrée ou si la connexion échoue.
  Future<void> imprimerFacture(Invoice invoice,
      {ReceiptSettings? settings}) async {
    final ip = await getDefaultPrinterIp();
    if (ip == null || ip.isEmpty) {
      throw StateError(
          "Aucune imprimante Wi-Fi configurée. Ouvrez l'aperçu du reçu puis saisissez son adresse IP.");
    }

    final (_, bytes) = await prepareReceiptBytes(invoice, settings: settings);

    Socket? socket;
    try {
      socket = await Socket.connect(ip, kEscPosPort,
          timeout: const Duration(seconds: 10));
      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
    } on SocketException catch (e) {
      throw StateError(
          "Connexion à l'imprimante $ip impossible. Vérifiez qu'elle est allumée et sur le même réseau Wi-Fi. (${e.message})");
    } catch (e) {
      throw StateError("Erreur d'impression : $e");
    } finally {
      // Fermeture : déclenche l'impression sur la plupart des modèles.
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}
