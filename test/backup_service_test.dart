// Tests du service de sauvegarde : export CSV et restauration JSON.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/product.dart';
import 'package:invoice_app/services/backup_service.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/product_service.dart';
import 'package:invoice_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
  });

  test('invoicesToCsv génère le CSV avec échappement et une ligne par article',
      () {
    final inv = Invoice(
      id: '1234567890',
      clientName: 'Dupont; & Fils',
      createdAt: DateTime(2026, 8, 15, 10, 30),
      items: const [
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
      items: const [
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
    await storage.saveInvoices([
      Invoice(
        id: 'abc123',
        clientName: 'Client A',
        createdAt: DateTime(2026, 8, 15),
        items: const [InvoiceItem(name: 'Article 1', quantity: 3, unitPrice: 100)],
      ),
    ]);
    await ProductService().saveProducts([
      Product(id: 'p1', name: 'Produit 1', category: 'Catégorie'),
    ]);
    await HistoryService().saveClientName('Client A');
    await HistoryService().saveProductName('Article 1');

    final json = await BackupService().createBackupJson();
    expect(json, contains('"invoices"'));
    expect(json, contains('"clientNames"'));

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

  test('decodeBackup rejette un fichier invalide', () {
    expect(
      () => BackupService().decodeBackup('pas du json {'),
      throwsFormatException,
    );
    expect(
      () => BackupService().decodeBackup('{"foo": 1}'),
      returnsNormally,
    );
  });
}
