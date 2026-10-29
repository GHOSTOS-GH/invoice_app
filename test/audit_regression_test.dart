// test/audit_regression_test.dart
// Tests de non-régression nommés d'après les points de l'audit de recette
// (a → n). Chaque test protège un comportement validé pendant la refonte.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/product.dart';
import 'package:invoice_app/models/receipt_settings.dart';
import 'package:invoice_app/screens/history_screen.dart';
import 'package:invoice_app/screens/invoice_detail_screen.dart';
import 'package:invoice_app/screens/new_invoice_screen.dart';
import 'package:invoice_app/screens/settings/security_page.dart';
import 'package:invoice_app/screens/stats_screen.dart';
import 'package:invoice_app/services/auth_service.dart';
import 'package:invoice_app/services/backup_service.dart';
import 'package:invoice_app/services/document_settings_service.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/pdf/invoice_pdf_builder.dart';
import 'package:invoice_app/services/product_image_store.dart';
import 'package:invoice_app/services/product_service.dart';
import 'package:invoice_app/services/receipt_builder.dart';
import 'package:invoice_app/utils/constants.dart';
import 'package:invoice_app/utils/formatters.dart';

// ---------------------------------------------------------------------------
// Outils
// ---------------------------------------------------------------------------

/// 7 500 FCFA d'articles, remise 500, TVA 10 % → 7 700 FCFA à payer.
Invoice _invoice({
  String id = '20261012093000',
  String clientName = 'Aïssatou Diop',
  String? notes = 'Livraison lundi matin',
  int discount = 500,
  double taxRate = 10,
  List<InvoiceItem>? items,
}) =>
    Invoice(
      id: id,
      clientName: clientName,
      createdAt: DateTime(2026, 10, 12, 9, 30),
      items: items ??
          [
            InvoiceItem(id: 'i1', name: 'Riz parfumé', quantity: 2, unitPrice: 1500),
            InvoiceItem(id: 'i2', name: 'Huile rouge', quantity: 1, unitPrice: 2500),
            InvoiceItem(id: 'i3', name: 'Savon', quantity: 4, unitPrice: 500),
          ],
      notes: notes,
      discount: discount,
      taxRate: taxRate,
    );

const String _productsJson = '''
[
  {"id": "p1", "name": "Riz parfumé", "category": "Céréales"},
  {"id": "p2", "name": "Huile rouge", "category": "Épicerie"},
  {"id": "p3", "name": "Savon", "category": "Hygiène"}
]
''';

void _resetData() {
  InvoiceRepository().resetForTests();
  HistoryService.resetCacheForTests();
}

void _setSurface(WidgetTester tester, {Size size = const Size(900, 1800)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DocumentSettingsService.settingsNotifier.value = DocumentSettings.defaults();
  });

  // ---------------------------------------------------------------- a) total

  testWidgets(
      'a) un seul total (payableTotal) cohérent entre détail, historique, '
      'stats, CSV et reçu', (tester) async {
    _resetData();
    final invoice = _invoice();
    expect(invoice.subtotal, 7500);
    expect(invoice.payableTotal, 7700);

    _setSurface(tester);
    await InvoiceRepository().replaceAll([invoice]);

    // Détail
    await _pump(tester, InvoiceDetailScreen(invoice: invoice, onInvoiceUpdated: () {}));
    expect(find.text(formatCurrency(7700)), findsWidgets);

    // Historique (total de la ligne et total de la liste). Le squelette de
    // chargement a une animation : on avance image par image.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(onInvoiceUpdated: () {})),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text(formatCurrency(7700)), findsWidgets);

    // Statistiques (chiffre d'affaires de la période). Pas de
    // pumpAndSettle : le squelette a une animation tant que rien n'est prêt.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Période « Tout » : la facture de test n'est pas dans les 7 derniers jours.
    await tester.tap(find.text('Tout'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text(formatCurrency(7700)), findsWidgets);

    // CSV
    final csv = BackupService().invoicesToCsv([invoice]);
    expect(csv, contains(';7700;'));

    // Reçu thermique
    final receipt = ReceiptBuilder.buildContent(invoice, ReceiptSettings.defaults());
    final receiptText = receipt.plan
        .whereType<ReceiptLine>()
        .map((line) => line.text)
        .join('\n');
    expect(receiptText, contains('7 700 FCFA'));

  });

  test('a) le PDF est produit depuis le même total à payer', () async {
    final invoice = _invoice();
    expect(invoice.payableTotal, 7700);

    // Le texte du PDF n'est pas extractible dans les tests (glyphes
    // sous-ensemblés) : on vérifie un PDF valide et non vide, produit par le
    // moteur unique qui lit `invoice.payableTotal`.
    final pdf = await const InvoicePdfBuilder().build(invoice);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length, greaterThan(1000));
  });

  // ------------------------------------------------------------- b) pages

  test('b) PDF multi-pages sans exception (80 articles)', () async {
    final invoice = _invoice(
      discount: 0,
      taxRate: 0,
      items: List<InvoiceItem>.generate(
        80,
        (index) => InvoiceItem(
          id: 'item-$index',
          name: 'Article ${index + 1} avec un libellé un peu long',
          quantity: index % 5 + 1,
          unitPrice: 1000 + index * 75,
        ),
      ),
    );

    final pdf = await const InvoicePdfBuilder().build(invoice);
    final text = String.fromCharCodes(pdf);
    final pages = RegExp(r'/Type\s*/Page\b').allMatches(text).length;

    expect(pages, greaterThan(1));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  // ------------------------------------------- c) prix vide = 1 FCFA

  testWidgets('c) prix vide = 1 FCFA par défaut', (tester) async {
    SharedPreferences.setMockInitialValues({'products': _productsJson});
    _resetData();
    _setSurface(tester, size: const Size(900, 1600));
    await _pump(tester, NewInvoiceScreen(onInvoiceCreated: () {}));

    await tester.tap(find.text('Ajouter un article'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appuyez pour choisir un produit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riz parfumé'));
    await tester.pumpAndSettle();

    // La quantité reste obligatoire : sans elle, rien n'est ajouté.
    await tester.tap(find.text('Ajouter l\'article'));
    await tester.pumpAndSettle();

    expect(find.text('Prix obligatoire (entier supérieur à 0)'), findsNothing);
    expect(find.text('Quantité obligatoire (entier supérieur à 0)'),
        findsOneWidget);
    expect(find.text('Nouvel article'), findsOneWidget, reason: 'feuille ouverte');
    // Aucun article n'a rejoint la facture.
    expect(find.text('Aucun article'), findsOneWidget);

    // Prix laissé vide : l'article est ajouté à 1 FCFA (modifiable ensuite).
    await tester.enterText(
      find.widgetWithText(TextField, 'Quantité *'),
      '2',
    );
    await tester.tap(find.text('Ajouter l\'article'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun article'), findsNothing);
    expect(find.text('2 × 1 FCFA'), findsOneWidget);

    // Prix saisi à 0 : même règle, 1 FCFA.
    await tester.tap(find.byTooltip('Ajouter un article'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appuyez pour choisir un produit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huile rouge'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Quantité *'),
      '3',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Prix unitaire (FCFA)'),
      '0',
    );
    await tester.tap(find.text('Ajouter l\'article'));
    await tester.pumpAndSettle();

    expect(find.text('3 × 1 FCFA'), findsOneWidget);
  });

  // ---------------------------------------------------------- d) stats

  testWidgets('d) statistiques rafraîchies après création', (tester) async {
    _resetData();
    _setSurface(tester);
    await _pump(tester, const StatsScreen());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Aucune donnée pour le moment'), findsOneWidget);

    await InvoiceRepository().add(
      Invoice(
        id: 'inv-stats',
        clientName: 'Client Stats',
        createdAt: DateTime.now(),
        items: [InvoiceItem(id: 's1', name: 'Article', quantity: 2, unitPrice: 1500)],
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Aucune donnée pour le moment'), findsNothing);
    expect(find.text(formatCurrency(3000)), findsWidgets);
  });

  // --------------------------------------------- e) saisies non validées

  testWidgets('e) modifications non validées conservées', (tester) async {
    _resetData();
    _setSurface(tester);
    final invoice = _invoice();
    await InvoiceRepository().replaceAll([invoice]);
    await _pump(tester, InvoiceDetailScreen(invoice: invoice, onInvoiceUpdated: () {}));

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();

    final quantities = find.widgetWithText(TextField, 'Quantité');
    await tester.enterText(quantities.at(0), '7');
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes (optionnel)'),
      'Note non validée',
    );
    await tester.pump();

    // Supprimer la dernière ligne ne touche pas aux saisies en cours.
    await tester.tap(find.byTooltip('Supprimer').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    final quantityFields = find.widgetWithText(TextField, 'Quantité');
    expect(quantityFields, findsNWidgets(2));
    expect(
      tester.widget<TextField>(quantityFields.at(0)).controller!.text,
      '7',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Notes (optionnel)'))
          .controller!
          .text,
      'Note non validée',
    );
    expect(find.text('Savon'), findsNothing);
  });

  // ------------------------------------------------- f) Annuler restaure tout

  testWidgets('f) Annuler restaure tout', (tester) async {
    _resetData();
    _setSurface(tester);
    final invoice = _invoice();
    await InvoiceRepository().replaceAll([invoice]);
    await _pump(tester, InvoiceDetailScreen(invoice: invoice, onInvoiceUpdated: () {}));

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Nom du client'),
      'Client Renommé',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes (optionnel)'),
      'Notes modifiées',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Remise (FCFA)'),
      '1000',
    );
    await tester.enterText(find.widgetWithText(TextField, 'TVA (%)'), '5');
    await tester.enterText(
      find.widgetWithText(TextField, 'Quantité').at(0),
      '9',
    );
    await tester.tap(find.byTooltip('Supprimer').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Riz parfumé'), findsNothing);

    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();

    expect(find.text('Aïssatou Diop'), findsOneWidget);
    expect(find.text('Livraison lundi matin'), findsOneWidget);
    expect(find.text('Riz parfumé'), findsOneWidget);
    expect(find.text('Huile rouge'), findsOneWidget);
    expect(find.text('Savon'), findsOneWidget);
    expect(find.text(formatCurrency(7700)), findsWidgets);
    // La facture enregistrée n'a pas bougé.
    expect(InvoiceRepository().invoices.single.clientName, 'Aïssatou Diop');
    expect(InvoiceRepository().invoices.single.items.length, 3);
  });

  // ------------------------------------------- g) suppression sans mélange

  testWidgets('g) suppression d’articles sans mélange des valeurs',
      (tester) async {
    _resetData();
    _setSurface(tester);
    final invoice = _invoice();
    await InvoiceRepository().replaceAll([invoice]);
    await _pump(tester, InvoiceDetailScreen(invoice: invoice, onInvoiceUpdated: () {}));

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Supprimer').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(find.text('Huile rouge'), findsNothing);
    final quantities = find.widgetWithText(TextField, 'Quantité');
    expect(quantities, findsNWidgets(2));
    expect(tester.widget<TextField>(quantities.at(0)).controller!.text, '2');
    expect(tester.widget<TextField>(quantities.at(1)).controller!.text, '4');
    final prices = find.widgetWithText(TextField, 'Prix unitaire');
    expect(tester.widget<TextField>(prices.at(0)).controller!.text, '1500');
    expect(tester.widget<TextField>(prices.at(1)).controller!.text, '500');
  });

  // ------------------------------------- h) autocomplétion + dernier prix

  testWidgets('h) autocomplétion et dernier prix par client', (tester) async {
    SharedPreferences.setMockInitialValues({
      'products': _productsJson,
      'history_client_names': <String>['Mamadou Diallo'],
    });
    _resetData();
    _setSurface(tester, size: const Size(900, 1600));

    await InvoiceRepository().replaceAll([
      Invoice(
        id: 'old',
        clientName: 'Mamadou Diallo',
        createdAt: DateTime(2026, 10, 1, 8),
        items: [
          InvoiceItem(id: 'o1', name: 'Riz parfumé', quantity: 1, unitPrice: 1200),
        ],
      ),
    ]);

    await _pump(tester, NewInvoiceScreen(onInvoiceCreated: () {}));
    await tester.tap(find.text('Ajouter un article'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Nom du client (optionnel)'),
      'mam',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('client-option-Mamadou Diallo')),
      findsOneWidget,
    );
    // Choisir la suggestion fige le client : le dernier prix devient utilisable.
    await tester.tap(find.byKey(const ValueKey('client-option-Mamadou Diallo')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appuyez pour choisir un produit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riz parfumé'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Prix unitaire (FCFA)'))
          .controller!
          .text,
      '1200',
    );
    expect(find.textContaining('Dernier prix pour Mamadou Diallo'), findsOneWidget);
  });

  // --------------------------------------------- i) images produit migrées

  test('i) images produit conservées après migration', () async {
    final temp = await Directory.systemTemp.createTemp('audit_images_');
    addTearDown(() => temp.delete(recursive: true));

    final legacy = File('${temp.path}${Platform.pathSeparator}ancienne.jpg');
    await legacy.writeAsBytes(<int>[7, 8, 9]);

    await ProductService().saveProducts([
      Product(
        id: 'p-legacy',
        name: 'Produit ancien',
        category: 'Divers',
        imagePath: legacy.path, // ancien chemin absolu
      ),
    ]);

    final store = ProductImageStore(documentsDirectory: () async => temp);
    await store.migrateLegacyImages();

    final migrated = (await ProductService().loadProducts()).single;
    expect(migrated.imagePath, isNotNull);
    expect(migrated.imagePath, isNot(contains('/')));
    expect(migrated.imagePath, isNot(contains(r'\')));
    final file = store.resolve(migrated.imagePath);
    expect(await file!.exists(), isTrue);
    expect(await file.readAsBytes(), <int>[7, 8, 9]);
    // L'original n'est jamais supprimé.
    expect(await legacy.exists(), isTrue);
  });

  // ------------------------------- j) restauration v1, v2 + sécurité

  test('j) restauration v1 et v2 avec sauvegarde de sécurité', () async {
    _resetData();
    final temp = await Directory.systemTemp.createTemp('audit_backup_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ProductImageStore(documentsDirectory: () async => temp);
    final service = BackupService(
      imageStore: store,
      documentsDirectory: () async => temp,
    );

    // v1 : facture sans ids d'articles, prix décimal, pas de réglages.
    const v1 = '''
    {
      "app": "Gestion de Factures",
      "backupVersion": "1.0",
      "invoices": [
        {
          "id": "1700000000000",
          "clientName": "Client V1",
          "createdAt": "2026-01-05T10:00:00.000",
          "items": [{"name": "Article", "quantity": 2, "unitPrice": 99.99}],
          "status": "livree"
        }
      ]
    }
    ''';
    final result1 = await service.restoreFromJson(v1);
    expect(result1.invoiceCount, 1);
    final restoredV1 = InvoiceRepository().invoices.single;
    expect(restoredV1.items.single.unitPrice, 100);
    expect(restoredV1.items.single.id, isNotEmpty);

    // v2 : export puis restauration, avec les réglages du document.
    const settings = DocumentSettings(businessName: 'Boutique Audit');
    await DocumentSettingsService.instance.saveSettings(settings);
    final v2 = await service.createBackupJson();
    expect(jsonDecode(v2)['backupVersion'], '2.0');
    expect(v2, contains('"documentSettings"'));

    await InvoiceRepository().replaceAll([]);
    await DocumentSettingsService.instance.resetToDefaults();
    final result2 = await service.restoreFromJson(v2);
    expect(result2.invoiceCount, 1);
    expect(InvoiceRepository().invoices.single.clientName, 'Client V1');
    expect(
      DocumentSettingsService.settingsNotifier.value.businessName,
      'Boutique Audit',
    );

    // Deux sauvegardes de sécurité attendues (une par restauration).
    final backups = Directory('${temp.path}${Platform.pathSeparator}backups')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('pre_restore_'))
        .toList();
    expect(backups.length, 2);
  });

  // ------------------------------------------- k) code admin modifiable

  testWidgets('k) code admin modifiable puis reconnexion', (tester) async {
    _resetData();
    _setSurface(tester, size: const Size(700, 1800));
    await _pump(tester, const SecurityPage());

    await tester.enterText(
      find.widgetWithText(TextField, 'Code actuel'),
      '0000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nouvel identifiant'),
      'gerant',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nouveau code'),
      '9876',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirmation du nouveau code'),
      '9876',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('Identifiant et code mis à jour'), findsOneWidget);

    final auth = AuthService();
    expect(await auth.login('Admin', '0000'), isFalse);
    expect(await auth.login('gerant', '0000'), isFalse);
    expect(await auth.login('gerant', '9876'), isTrue);
  });

  test('k) code actuel erroné : changement refusé', () async {
    final result = await AuthService().changeCredentials(
      currentPassword: 'mauvais',
      newUsername: 'gerant',
      newPassword: '9876',
    );
    expect(result, CredentialChangeResult.wrongCurrentPassword);
    expect(await AuthService().login('Admin', '0000'), isTrue);
  });

  // ------------------------------------------------------ l) formatNumber

  test('l) formatNumber : entiers, séparateurs, négatifs, zéro', () {
    expect(formatNumber(0), '0');
    expect(formatNumber(999), '999');
    expect(formatNumber(1000), '1\u{00A0}000');
    expect(formatNumber(1234567), '1\u{00A0}234\u{00A0}567');
    expect(formatNumber(-1234567), '-1\u{00A0}234\u{00A0}567');
    expect(formatNumber(1234567, sep: ' '), '1 234 567');
    expect(formatCurrency(7700), '7\u{00A0}700 FCFA');
    // Jamais de décimale, même pour de très grands montants.
    expect(formatNumber(99999999), '99\u{00A0}999\u{00A0}999');
    expect(formatCurrency(99999999), isNot(contains(',')));
    expect(formatCurrency(99999999), isNot(contains('.')));
  });

  // ------------------------------------- m) lecture d'un stockage ancien

  test('m) lecture d’un stockage ancien (décimales, sans ids)', () {
    final invoice = Invoice.fromJson(<String, dynamic>{
      'id': '1700000000000',
      'clientName': 'Ancien Client',
      'createdAt': '2025-02-15T14:30:00.000',
      'items': [
        {'name': 'Article décimal', 'quantity': 2, 'unitPrice': 99.99},
        {'name': 'Article remisé', 'quantity': 1, 'unitPrice': 2500.4, 'id': ''},
      ],
      'status': 'statutInconnu',
      'notes': null,
      'discount': 10.5,
      'taxRate': 5,
    });

    expect(invoice.items.first.unitPrice, 100);
    expect(invoice.items.last.unitPrice, 2500);
    expect(invoice.items.every((item) => item.id.isNotEmpty), isTrue);
    expect(invoice.discount, 11);
    expect(invoice.status, InvoiceStatus.enCours);
    expect(invoice.payableTotal, 100 * 2 + 2500 - 11 + ((2700 - 11) * 5 / 100).round());

    // Un produit ancien peut porter un chemin absolu : il reste lisible.
    final product = Product.fromJson(<String, dynamic>{
      'id': 'p-old',
      'name': 'Ancien produit',
      'category': 'Divers',
      'imagePath': r'C:\ancien\photo.jpg',
    });
    expect(product.imagePath, r'C:\ancien\photo.jpg');
  });

  // ------------------------------ n) réglages de facture : défauts sûrs

  test('n) réglages de facture : défauts sur JSON absent ou corrompu',
      () async {
    // Absent : valeurs par défaut (et copie des infos du reçu s'il existe).
    final absent = await DocumentSettingsService().loadSettings();
    expect(absent, DocumentSettings.defaults());

    // Corrompu : retour aux défauts, sans exception.
    SharedPreferences.setMockInitialValues({
      Constants.documentSettingsKey: '{"version":1,"businessName":',
    });
    DocumentSettingsService.settingsNotifier.value = DocumentSettings.defaults();
    final corrupted = await DocumentSettingsService().loadSettings();
    expect(corrupted, DocumentSettings.defaults());

    // Ancien JSON partiel : les champs présents sont conservés.
    SharedPreferences.setMockInitialValues({
      Constants.documentSettingsKey: '{"businessName":"Ancien"}',
    });
    final partial = await DocumentSettingsService().loadSettings();
    expect(partial.businessName, 'Ancien');
    expect(partial.template, DocumentTemplate.modern);
    expect(partial.showLogo, isTrue);
    expect(partial.imageQuality, DocumentImageQuality.standard);
  });
}
