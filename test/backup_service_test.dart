// Tests du service de sauvegarde : export CSV, sauvegarde v2 (images et
// paramètres), restauration v1, validation et retour arrière.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/product.dart';
import 'package:invoice_app/services/backup_service.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/product_image_store.dart';
import 'package:invoice_app/services/product_service.dart';
import 'package:invoice_app/services/storage_service.dart';
import 'package:invoice_app/utils/constants.dart';

Invoice _invoice(String id, {String clientName = 'Client A'}) => Invoice(
      id: id,
      clientName: clientName,
      createdAt: DateTime(2026, 8, 15),
      items: [InvoiceItem(name: 'Article 1', quantity: 3, unitPrice: 100)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    InvoiceRepository().resetForTests();
    HistoryService.resetCacheForTests();
  });

  test('invoicesToCsv génère le CSV avec échappement et une ligne par article',
      () {
    final inv = Invoice(
      id: '1234567890',
      clientName: 'Dupont; & Fils',
      createdAt: DateTime(2026, 8, 15, 10, 30),
      items: [
        InvoiceItem(name: 'Riz "parfumé"', quantity: 5, unitPrice: 1500),
        InvoiceItem(name: 'Huile', quantity: 2, unitPrice: 2501),
      ],
      status: InvoiceStatus.livree,
      notes: 'Note avec ; point-virgule',
    );

    final csv = BackupService().invoicesToCsv([inv]);

    // En-tête + 2 lignes d'articles
    final lines = csv.split('\r\n');
    expect(lines.length, 3);
    expect(
      lines.first,
      'Date;Réf;Client;Statut;Article;Quantité;Prix unitaire;'
      'Sous-total article;Sous-total facture;Remise;TVA;Total à payer;Notes',
    );

    // Échappement des champs contenant « ; » ou des guillemets
    expect(csv, contains('"Dupont; & Fils"'));
    expect(csv, contains('"Riz ""parfumé"""'));
    // Montants entiers, jamais de décimale
    expect(csv, isNot(contains('.0')));
    expect(csv, isNot(contains('2501.0')));

    // Première ligne : totaux de la facture renseignés (7 500 + 5 002)
    expect(
      lines[1],
      contains(';5;1500;7500;12502;0;0;12502;"Note avec ; point-virgule"'),
    );
    // Ligne suivante : totaux facture et notes VIDES (sommes Excel justes)
    expect(lines[2], contains(';2;2501;5002;;;;;'));
  });

  test('invoicesToCsv remplit remise, TVA et total à payer sur la 1re ligne',
      () {
    final inv = Invoice(
      id: '1234567890',
      clientName: 'Client',
      createdAt: DateTime(2026, 8, 15, 10, 30),
      items: [
        InvoiceItem(name: 'A', quantity: 1, unitPrice: 10000),
        InvoiceItem(name: 'B', quantity: 2, unitPrice: 2500),
      ],
      discount: 500,
      taxRate: 18,
    );

    final lines = BackupService().invoicesToCsv([inv]).split('\r\n');
    // Sous-total 15 000 → TVA (15 000 − 500) × 18 % = 2 610 → 17 110
    expect(lines[1], endsWith(';10000;15000;500;2610;17110;'));
    expect(lines[2], endsWith(';2;2500;5000;;;;;'));
  });

  test('sauvegarde JSON puis restauration conserve les données', () async {
    final storage = StorageService();
    await storage.saveInvoices([_invoice('abc123')]);
    await ProductService().saveProducts([
      Product(id: 'p1', name: 'Produit 1', category: 'Catégorie'),
    ]);
    await HistoryService().saveClientName('Client A');
    await HistoryService().saveProductName('Article 1');

    final json = await BackupService().createBackupJson();
    expect(json, contains('"invoices"'));
    expect(json, contains('"clientNames"'));
    expect(json, contains('"backupVersion": "2.0"'));

    // On simule un appareil vide puis on restaure
    SharedPreferences.setMockInitialValues({});
    await BackupService().restoreFromJson(json);

    final invoices = await storage.loadInvoices();
    expect(invoices.length, 1);
    expect(invoices.first.clientName, 'Client A');
    expect(invoices.first.items.first.quantity, 3);
    expect(invoices.first.items.first.unitPrice, 100);

    final products = await ProductService().loadProducts();
    expect(products.length, 1);
    expect(products.first.name, 'Produit 1');

    final clients = await HistoryService().getClientNames();
    expect(clients, contains('Client A'));
    final historyProducts = await HistoryService().getProductNames();
    expect(historyProducts, contains('Article 1'));
  });

  test('aller-retour v2 avec image, paramètres et sauvegarde de sécurité',
      () async {
    final temp = await Directory.systemTemp.createTemp('invoice_backup_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ProductImageStore(documentsDirectory: () async => temp);
    await store.ensureDirectory();
    await store.writeBytes(
        'photo.jpg', Uint8List.fromList(<int>[1, 2, 3, 4]));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.receiptSettingsKey, '{"showLogo":false}');
    await prefs.setString('document_settings', '{"paper":"A4"}');

    await InvoiceRepository().replaceAll([_invoice('v2')]);
    await ProductService().saveProducts([
      Product(
        id: 'p1',
        name: 'Produit',
        category: 'Catégorie',
        imagePath: 'photo.jpg',
      ),
    ]);

    final service = BackupService(
      imageStore: store,
      documentsDirectory: () async => temp,
    );
    final json = await service.createBackupJson();
    expect(json, contains('"productImages"'));
    expect(json, contains('"receiptSettings"'));
    expect(json, contains('"documentSettings"'));

    // État vidé avant restauration.
    await InvoiceRepository().replaceAll([]);
    await ProductService().saveProducts([]);
    await prefs.remove(Constants.receiptSettingsKey);
    await prefs.remove('document_settings');
    final imageFile =
        File('${temp.path}${Platform.pathSeparator}product_images'
            '${Platform.pathSeparator}photo.jpg');
    await imageFile.delete();

    final result = await service.restoreFromJson(json);
    expect(result.invoiceCount, 1);
    expect(result.productCount, 1);

    expect(await imageFile.exists(), isTrue);
    expect(await imageFile.readAsBytes(), <int>[1, 2, 3, 4]);
    expect((await ProductService().loadProducts()).single.imagePath,
        'photo.jpg');
    expect(prefs.getString(Constants.receiptSettingsKey),
        '{"showLogo":false}');
    expect(prefs.getString('document_settings'), '{"paper":"A4"}');

    final backups = Directory(
            '${temp.path}${Platform.pathSeparator}backups')
        .listSync()
        .whereType<File>()
        .toList();
    expect(backups.length, 1,
        reason: 'une sauvegarde de sécurité avant restauration');
    expect(backups.single.path, contains('pre_restore_'));
  });

  test('un fichier v1 reste restaurable', () async {
    final temp = await Directory.systemTemp.createTemp('invoice_backup_v1_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ProductImageStore(documentsDirectory: () async => temp);

    const v1 = '''
    {
      "app": "Gestion de Factures",
      "backupVersion": "1.0",
      "invoices": [
        {
          "id": "1700000000000",
          "clientName": "Ancien Client",
          "createdAt": "2026-01-02T10:30:00.000",
          "items": [{"name": "Riz", "quantity": 2, "unitPrice": 99.99}],
          "status": "livree"
        }
      ],
      "products": [
        {"id": "p1", "name": "Produit", "category": "Catégorie"}
      ],
      "clientNames": ["Ancien Client"],
      "productNames": ["Riz"]
    }
    ''';

    final service = BackupService(
      imageStore: store,
      documentsDirectory: () async => temp,
    );
    final result = await service.restoreFromJson(v1);

    expect(result.invoiceCount, 1);
    expect(InvoiceRepository().invoices.single.items.single.unitPrice, 100);
    expect(InvoiceRepository().invoices.single.payableTotal, 200);
    expect((await ProductService().loadProducts()).single.name, 'Produit');
    expect(await HistoryService().getClientNames(), contains('Ancien Client'));
  });

  test('un fichier invalide ne modifie aucune donnée', () async {
    final temp = await Directory.systemTemp.createTemp('invoice_backup_bad_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ProductImageStore(documentsDirectory: () async => temp);
    final service = BackupService(
      imageStore: store,
      documentsDirectory: () async => temp,
    );

    await InvoiceRepository().replaceAll([_invoice('keep')]);
    await ProductService().saveProducts([
      Product(id: 'keep-p', name: 'Gardé', category: 'Catégorie'),
    ]);

    await expectLater(
      service.restoreFromJson('{"invoices": [{"id": 42}], "products": []}'),
      throwsFormatException,
    );

    expect(InvoiceRepository().invoices.single.id, 'keep');
    expect((await ProductService().loadProducts()).single.id, 'keep-p');
  });

  test('une restauration échouée revient à l’état précédent', () async {
    final temp = await Directory.systemTemp.createTemp('invoice_backup_fail_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ProductImageStore(documentsDirectory: () async => temp);
    final service = BackupService(
      imageStore: store,
      documentsDirectory: () async => temp,
    );

    await InvoiceRepository().replaceAll([_invoice('before')]);
    await ProductService().saveProducts([
      Product(id: 'before-p', name: 'Avant', category: 'Catégorie'),
    ]);

    const incoming = '''
    {
      "backupVersion": "2.0",
      "invoices": [
        {
          "id": "new",
          "clientName": "Nouveau",
          "createdAt": "2026-02-01T10:00:00.000",
          "items": [{"name": "Nouvel article", "quantity": 1, "unitPrice": 500}]
        }
      ],
      "products": [
        {"id": "new-p", "name": "Nouveau produit", "category": "Catégorie"}
      ]
    }
    ''';

    service.debugAfterImagesWritten = () => throw StateError('échec simulé');

    await expectLater(service.restoreFromJson(incoming), throwsStateError);

    expect(InvoiceRepository().invoices.single.id, 'before');
    expect((await ProductService().loadProducts()).single.id, 'before-p');
  });

  test('decodeBackup rejette un fichier invalide', () {
    expect(
      () => BackupService().decodeBackup('pas du json {'),
      throwsFormatException,
    );
    expect(
      () => BackupService().decodeBackup('{"foo": 1}'),
      returnsNormally,
    );
    expect(
      () => BackupService().decodeBackup('{"products": [{"name": "Sans id"}]}'),
      throwsFormatException,
    );
  });

  test('une chaîne JSON lisible mais décimale reste valide pour decodeBackup',
      () {
    final json = jsonEncode({
      'invoices': [
        {
          'id': '1',
          'clientName': 'C',
          'createdAt': '2026-01-02T10:30:00.000',
          'items': [
            {'name': 'Riz', 'quantity': 1, 'unitPrice': 12.7},
          ],
        }
      ],
    });
    final result = BackupService().decodeBackup(json);
    expect(result.invoiceCount, 1);
  });
}
