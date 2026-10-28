// lib/services/backup_service.dart
// Export CSV, sauvegarde complète JSON (v2 : images produit + paramètres) et
// restauration sécurisée des données.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice.dart';
import '../models/product.dart';
import '../utils/constants.dart';
import 'document_settings_service.dart';
import 'history_service.dart';
import 'invoice_repository.dart';
import 'product_image_store.dart';
import 'product_service.dart';
import 'receipt_settings_service.dart';

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

/// Sauvegarde entièrement décodée et validée.
class _ParsedBackup {
  final List<Invoice> invoices;
  final List<Product> products;
  final List<String> clientNames;
  final List<String> productNames;
  final Map<String, Uint8List> productImages;
  final String? receiptSettings;
  final String? documentSettings;

  const _ParsedBackup({
    required this.invoices,
    required this.products,
    required this.clientNames,
    required this.productNames,
    required this.productImages,
    required this.receiptSettings,
    required this.documentSettings,
  });

  RestoreResult get result => RestoreResult(
        invoiceCount: invoices.length,
        productCount: products.length,
        clientCount: clientNames.length,
      );
}

class BackupService {
  BackupService({
    ProductImageStore? imageStore,
    Future<Directory> Function()? documentsDirectory,
  })  : _imageStore = imageStore ?? ProductImageStore.instance,
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  static const String _backupVersion = '2.0';
  static const int _maxSafetyBackups = 3;

  final ProductImageStore _imageStore;
  final Future<Directory> Function() _documentsDirectory;

  /// Crochet de test : appelé juste après l'écriture des images, avant les
  /// données, pour vérifier le retour arrière en cas d'échec.
  @visibleForTesting
  void Function()? debugAfterImagesWritten;

  // ---------- Export CSV ----------

  /// Génère le contenu CSV des [invoices] (une ligne par article).
  ///
  /// Séparateur « ; » (convention française) pour une ouverture directe
  /// dans Excel. Tous les montants sont des entiers FCFA, écrits sans
  /// décimale. Les totaux de la facture (sous-total, remise, TVA, total à
  /// payer) et les notes ne sont remplis que sur la PREMIÈRE ligne de
  /// chaque facture : les sommes Excel ne comptent ainsi pas plusieurs
  /// fois le même total.
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
        'Sous-total article',
        'Sous-total facture',
        'Remise',
        'TVA',
        'Total à payer',
        'Notes',
      ],
    ];

    for (final inv in invoices) {
      final date = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR').format(inv.createdAt);
      final ref = _refId(inv.id);
      final notes = inv.notes ?? '';
      var first = true;
      for (final item in inv.items) {
        rows.add([
          date,
          ref,
          inv.clientName,
          inv.status.label,
          item.name,
          '${item.quantity}',
          '${item.unitPrice}',
          '${item.subtotal}',
          first ? '${inv.subtotal}' : '',
          first ? '${inv.discountApplied}' : '',
          first ? '${inv.taxAmount}' : '',
          first ? '${inv.payableTotal}' : '',
          first ? notes : '',
        ]);
        first = false;
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

  static String _refId(String id) =>
      id.length >= 6 ? '#${id.substring(id.length - 6)}' : id;

  // ---------- Sauvegarde complète JSON ----------

  /// Construit le JSON de sauvegarde complète (factures, produits,
  /// historiques, images produit et paramètres du document).
  Future<String> createBackupJson() async {
    final repository = InvoiceRepository();
    await repository.load();
    final products = await ProductService().loadProducts();
    final historyService = HistoryService();
    final clientNames = await historyService.getClientNames();
    final productNames = await historyService.getProductNames();
    final prefs = await SharedPreferences.getInstance();
    // Toujours présente : les réglages du document voyagent avec les données
    // (bruts s'ils existent déjà, sinon les valeurs par défaut).
    final documentSettings = prefs.getString(Constants.documentSettingsKey) ??
        jsonEncode(
          (await DocumentSettingsService.instance.loadSettings()).toJson(),
        );

    final backup = <String, dynamic>{
      'app': 'Gestion de Factures',
      'backupVersion': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'invoices': repository.invoices.map((i) => i.toJson()).toList(),
      'products': products.map((p) => p.toJson()).toList(),
      'clientNames': clientNames,
      'productNames': productNames,
      'productImages': await _collectProductImages(products),
      'documentSettings': documentSettings,
    };

    final receiptSettings = prefs.getString(Constants.receiptSettingsKey);
    if (receiptSettings != null) {
      backup['receiptSettings'] = receiptSettings;
    }

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// Décode et valide un fichier sans rien écrire (aperçu avant restauration).
  RestoreResult decodeBackup(String json) => _parseAndValidate(json).result;

  /// Restaure les données depuis un JSON de sauvegarde (remplace tout).
  ///
  /// 1. validation complète du fichier ;
  /// 2. sauvegarde de sécurité dans `documents/backups/` ;
  /// 3. écriture des images puis des données ;
  /// 4. notification du repository.
  ///
  /// En cas d'échec, l'état précédent est restauré avant de relancer l'erreur.
  Future<RestoreResult> restoreFromJson(String json) async {
    final parsed = _parseAndValidate(json);

    _ParsedBackup? previous;
    File? safetyFile;
    try {
      final safetyJson = await createBackupJson();
      previous = _parseAndValidate(safetyJson);
      safetyFile = await _writeSafetyBackup(safetyJson);
    } catch (error) {
      // Sans sauvegarde de sécurité, la restauration reste possible : le
      // retour arrière utilisera l'instantané mémoire s'il a pu être pris.
      debugPrint('BackupService : état précédent non capturé ($error)');
    }

    try {
      await _applyParsed(parsed);
    } catch (error) {
      debugPrint('BackupService : restauration échouée ($error)');
      await _rollback(previous, safetyFile);
      rethrow;
    }

    return parsed.result;
  }

  _ParsedBackup _parseAndValidate(String json) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const FormatException('Fichier de sauvegarde invalide');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Fichier de sauvegarde invalide');
    }

    final invoices = <Invoice>[];
    final invoicesRaw = decoded['invoices'];
    if (invoicesRaw != null) {
      if (invoicesRaw is! List) {
        throw const FormatException('Factures invalides dans la sauvegarde');
      }
      for (final entry in invoicesRaw) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Facture invalide dans la sauvegarde');
        }
        try {
          invoices.add(Invoice.fromJson(entry));
        } catch (_) {
          throw const FormatException('Facture invalide dans la sauvegarde');
        }
      }
    }

    final products = <Product>[];
    final productsRaw = decoded['products'];
    if (productsRaw != null) {
      if (productsRaw is! List) {
        throw const FormatException('Produits invalides dans la sauvegarde');
      }
      for (final entry in productsRaw) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Produit invalide dans la sauvegarde');
        }
        try {
          products.add(Product.fromJson(entry));
        } catch (_) {
          throw const FormatException('Produit invalide dans la sauvegarde');
        }
      }
    }

    final clientNamesRaw = decoded['clientNames'];
    final clientNames = clientNamesRaw is List
        ? clientNamesRaw.whereType<String>().toList()
        : <String>[];
    final productNamesRaw = decoded['productNames'];
    final productNames = productNamesRaw is List
        ? productNamesRaw.whereType<String>().toList()
        : <String>[];

    final images = <String, Uint8List>{};
    final imagesRaw = decoded['productImages'];
    if (imagesRaw != null) {
      if (imagesRaw is! Map) {
        throw const FormatException('Images produit invalides');
      }
      for (final entry in imagesRaw.entries) {
        final name = entry.key;
        final value = entry.value;
        if (name is! String ||
            value is! String ||
            name.contains('/') ||
            name.contains('\\')) {
          throw const FormatException('Images produit invalides');
        }
        try {
          images[name] = base64Decode(value);
        } catch (_) {
          throw FormatException('Image produit invalide : $name');
        }
      }
    }

    final receiptSettings = decoded['receiptSettings'];
    final documentSettings = decoded['documentSettings'];

    return _ParsedBackup(
      invoices: invoices,
      products: products,
      clientNames: clientNames,
      productNames: productNames,
      productImages: images,
      receiptSettings: receiptSettings is String ? receiptSettings : null,
      documentSettings: documentSettings is String ? documentSettings : null,
    );
  }

  Future<void> _applyParsed(
    _ParsedBackup parsed, {
    bool runDebugHook = true,
  }) async {
    // Images d'abord, puis données.
    for (final entry in parsed.productImages.entries) {
      await _imageStore.writeBytes(entry.key, entry.value);
    }
    if (runDebugHook) debugAfterImagesWritten?.call();

    await InvoiceRepository().replaceAll(parsed.invoices);
    await ProductService().saveProducts(parsed.products);
    await HistoryService().replaceAll(parsed.clientNames, parsed.productNames);

    final prefs = await SharedPreferences.getInstance();
    if (parsed.receiptSettings != null) {
      await prefs.setString(
          Constants.receiptSettingsKey, parsed.receiptSettings!);
      await ReceiptSettingsService().loadSettings();
    }
    if (parsed.documentSettings != null) {
      await prefs.setString(
        Constants.documentSettingsKey,
        parsed.documentSettings!,
      );
      await DocumentSettingsService.instance.loadSettings();
    }
  }

  Future<File?> _writeSafetyBackup(String json) async {
    try {
      final documents = await _documentsDirectory();
      final dir =
          Directory('${documents.path}${Platform.pathSeparator}backups');
      if (!await dir.exists()) await dir.create(recursive: true);

      final stamp = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
      final file =
          File('${dir.path}${Platform.pathSeparator}pre_restore_$stamp.json');
      await file.writeAsString(json, flush: true);
      await _pruneSafetyBackups(dir);
      return file;
    } catch (error) {
      debugPrint('BackupService : sauvegarde de sécurité impossible ($error)');
      return null;
    }
  }

  Future<void> _pruneSafetyBackups(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((entity) =>
              entity is File &&
              _fileName(entity.path).startsWith('pre_restore_') &&
              entity.path.endsWith('.json'))
          .cast<File>()
          .toList();
      files.sort((a, b) => _fileName(b.path).compareTo(_fileName(a.path)));
      for (final file in files.skip(_maxSafetyBackups)) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('BackupService : nettoyage des sauvegardes impossible ($error)');
    }
  }

  Future<void> _rollback(_ParsedBackup? previous, File? safetyFile) async {
    try {
      var restore = previous;
      if (safetyFile != null && await safetyFile.exists()) {
        try {
          restore = _parseAndValidate(await safetyFile.readAsString());
        } catch (error) {
          debugPrint(
              'BackupService : sauvegarde de sécurité illisible ($error)');
        }
      }
      if (restore == null) return;
      await _applyParsed(restore, runDebugHook: false);
    } catch (error) {
      debugPrint('BackupService : retour arrière impossible ($error)');
    }
  }

  Future<Map<String, String>> _collectProductImages(
      List<Product> products) async {
    final result = <String, String>{};
    for (final product in products) {
      final stored = product.imagePath;
      if (stored == null || stored.trim().isEmpty) continue;
      final file = _imageStore.resolve(stored);
      if (file == null) continue;
      try {
        if (!await file.exists()) continue;
        result[_fileName(stored)] = base64Encode(await file.readAsBytes());
      } catch (error) {
        debugPrint('BackupService : image illisible ($error)');
      }
    }
    return result;
  }

  static String _fileName(String path) =>
      path.split(RegExp(r'[/\\]')).last;

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
      // Laisser le temps à l'application destinataire de lire le fichier
      // avant de le supprimer : une suppression immédiate peut le rendre
      // illisible (erreur « fichier introuvable » côté destinataire).
      await Future.delayed(const Duration(seconds: 1));
      if (await file.exists()) await file.delete();
    }
  }
}
