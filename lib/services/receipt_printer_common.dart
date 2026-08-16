// lib/services/receipt_printer_common.dart
// Préparation commune des octets ESC/POS d'une facture, partagée par
// l'impression Bluetooth et l'impression Wi-Fi (même rendu de ticket).

import 'dart:io';
import 'dart:typed_data';

import '../models/invoice.dart';
import '../models/receipt_settings.dart';
import 'receipt_builder.dart';
import 'receipt_settings_service.dart';

/// Charge les paramètres du reçu (et le logo si présent), construit le
/// contenu du ticket et génère le flux ESC/POS.
///
/// Retourne le contenu (utilisé pour l'aperçu) et les octets prêts à
/// être envoyés à l'imprimante.
Future<(ReceiptContent, List<int>)> prepareReceiptBytes(
  Invoice invoice, {
  ReceiptSettings? settings,
}) async {
  final s = settings ?? await ReceiptSettingsService().loadSettings();
  Uint8List? logoBytes;
  if (s.logoPath != null) {
    try {
      logoBytes = await File(s.logoPath!).readAsBytes();
    } catch (_) {
      logoBytes = null;
    }
  }
  final content = ReceiptBuilder.buildContent(invoice, s,
      logoBytes: logoBytes);
  final bytes = await ReceiptBuilder.buildEscPosBytes(content);
  return (content, bytes);
}
