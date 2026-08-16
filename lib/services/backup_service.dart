// lib/services/backup_service.dart
// Export CSV, sauvegarde complète JSON et restauration des données.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/invoice.dart';
import '../models/product.dart';
import 'history_service.dart';
import 'product_service.dart';
import 'storage_service.dart';

/// Résultat du décodage / de la restauration d'une sauvegarde.
class RestoreResult {
  final int invoiceCount;
  final int productCount;
  final int clientCount;

  const RestoreResult({
    required this.invoiceCount,
    required this.productCount,
    required this.clientCount,
  });
}

class BackupService {
  static const String _backupVersion = '1.0';

  // ---------- Export CSV ----------

  /// Génère le contenu CSV des [invoices] (une ligne par article).
  ///
  /// Séparateur « ; » (convention française) pour une ouverture directe
  /// dans Excel. Les nombres entiers sont écrits sans décimale pour
  /// rester exploitables dans un tableur.
  String invoicesToCsv(List<Invoice> invoices) {
    final rows = <List<String>>[
      [
        'Date',
        'Réf',
        'Client',
        'Statut',
        'Article',
        'Quantité',
        'Prix unitaire',
        'Sous-total',
        'Total facture',
        'Notes',
      ],
    ];

    for (final inv in invoices) {
      final date = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR').format(inv.createdAt);
      final ref = _refId(inv.id);
      final total = _num(inv.total);
      final notes = inv.notes ?? '';
      for (final item in inv.items) {
        rows.add([
          date,
          ref,
          inv.clientName,
          inv.status.label,
          item.name,
          '${item.quantity}',
          _num(item.unitPrice),
          _num(item.subtotal),
          total,
          notes,
        ]);
      }
    }

    return rows.map((row) => row.map(_escapeCsv).join(';')).join('\r\n');
  }

  static String _escapeCsv(String field) {
    if (field.contains(';') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  static String _num(double value) =>
      value == value.roundToDouble() ? value.round().toString() : value.toString();

  static String _refId(String id) =>
      id.length >= 6 ? '#${id.substring(id.length - 6)}' : id;

  // ---------- Sauvegarde complète JSON ----------

  /// Construit le JSON de sauvegarde complète (factures, produits, historiques).
  Future<String> createBackupJson() async {
    final storage = StorageService();
    final productService = ProductService();
    final historyService = HistoryService();

    final invoices = await storage.loadInvoices();
    final products = await productService.loadProducts();
    final clientNames = await historyService.getClientNames();
    final productNames = await historyService.getProductNames();

    final backup = <String, dynamic>{
      'app': 'Gestion de Factures',
      'backupVersion': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'invoices': invoices.map((i) => i.toJson()).toList(),
      'products': products.map((p) => p.toJson()).toList(),
      'clientNames': clientNames,
      'productNames': productNames,
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// Décode un fichier de sauvegarde sans rien écrire (pour l'aperçu avant restauration).
  RestoreResult decodeBackup(String json) {
    final dynamic decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Fichier de sauvegarde invalide');
    }
    final invoicesRaw = decoded['invoices'];
    final productsRaw = decoded['products'];
    final clientNamesRaw = decoded['clientNames'];

    var invoiceCount = 0;
    if (invoicesRaw is List) {
      for (final e in invoicesRaw) {
        if (e is Map<String, dynamic>) {
          Invoice.fromJson(e); // valide la structure, jette en cas d'erreur
          invoiceCount++;
        }
      }
    }
    final productCount = productsRaw is List
        ? productsRaw.whereType<Map<String, dynamic>>().length
        : 0;
    final clientCount =
        clientNamesRaw is List ? clientNamesRaw.whereType<String>().length : 0;

    return RestoreResult(
      invoiceCount: invoiceCount,
      productCount: productCount,
      clientCount: clientCount,
    );
  }

  /// Restaure les données depuis un JSON de sauvegarde (remplace tout).
  Future<RestoreResult> restoreFromJson(String json) async {
    final result = decodeBackup(json);
    final dynamic decoded = jsonDecode(json) as Map<String, dynamic>;

    final invoices = <Invoice>[];
    final invoicesRaw = decoded['invoices'];
    if (invoicesRaw is List) {
      invoices.addAll(
        invoicesRaw.whereType<Map<String, dynamic>>().map(Invoice.fromJson),
      );
    }

    final products = <Product>[];
    final productsRaw = decoded['products'];
    if (productsRaw is List) {
      products.addAll(
        productsRaw.whereType<Map<String, dynamic>>().map(Product.fromJson),
      );
    }

    final clientNamesRaw = decoded['clientNames'];
    final productNamesRaw = decoded['productNames'];
    final clientNames =
        clientNamesRaw is List ? clientNamesRaw.whereType<String>().toList() : <String>[];
    final productNames =
        productNamesRaw is List ? productNamesRaw.whereType<String>().toList() : <String>[];

    await StorageService().saveInvoices(invoices);
    await ProductService().saveProducts(products);
    await HistoryService().replaceAll(clientNames, productNames);

    return result;
  }

  /// Ouvre le sélecteur de fichiers et lit un fichier JSON de sauvegarde.
  /// Retourne null si l'utilisateur annule.
  Future<({String filename, String content})?> pickAndReadJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Choisir un fichier de sauvegarde (.json)',
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;

    final Uint8List bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      throw const FormatException('Impossible de lire le fichier sélectionné');
    }

    return (
      filename: file.name,
      content: utf8.decode(bytes, allowMalformed: true),
    );
  }

  // ---------- Partage de fichiers ----------

  /// Partage un CSV (BOM UTF-8 ajouté pour les accents dans Excel).
  Future<void> shareCsv(String csv, String filename) async {
    await _shareBytes(utf8.encode('\uFEFF$csv'), filename, 'text/csv');
  }

  Future<void> shareBackupJson(String json, String filename) async {
    await _shareBytes(utf8.encode(json), filename, 'application/json');
  }

  Future<void> _shareBytes(List<int> bytes, String filename, String mime) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mime)],
        subject: filename,
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}
