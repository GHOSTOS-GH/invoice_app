// test/legacy_storage_test.dart
// Ouverture de l'application avec un stockage ANCIEN : factures décimales,
// articles sans ids, produits avec un chemin d'image absolu.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/main.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/product_image_store.dart';
import 'package:invoice_app/services/product_service.dart';
import 'package:invoice_app/utils/constants.dart';
import 'package:invoice_app/utils/formatters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const legacyInvoices = '''
  [
    {
      "id": "1700000000000",
      "clientName": "Ancien Client",
      "createdAt": "2026-01-02T10:30:00.000",
      "items": [
        {"name": "Riz", "quantity": 2, "unitPrice": 99.99},
        {"name": "Huile", "quantity": 1, "unitPrice": 1500.4}
      ],
      "status": "livree",
      "notes": null,
      "discount": 10.5,
      "taxRate": 18.0
    }
  ]
  ''';

  setUp(() {
    InvoiceRepository().resetForTests();
    HistoryService.resetCacheForTests();
  });

  test('un stockage ancien se charge sans crash et garde les totaux arrondis',
      () async {
    SharedPreferences.setMockInitialValues({
      Constants.invoicesKey: legacyInvoices,
      'history_client_names': <String>['Ancien Client'],
      'history_product_names': <String>['Riz', 'Huile'],
    });

    final repository = InvoiceRepository();
    await repository.load();

    expect(repository.hasLoadError, isFalse);
    final invoice = repository.invoices.single;
    expect(invoice.clientName, 'Ancien Client');
    expect(invoice.items.first.unitPrice, 100);
    expect(invoice.items.last.unitPrice, 1500);
    expect(invoice.total, 1700);
    expect(invoice.discount, 11);
    expect(invoice.taxAmount, 304);
    expect(invoice.payableTotal, 1993);

    // Les anciens articles sans id en reçoivent un, distinct et conservé.
    expect(invoice.items.first.id, isNotEmpty);
    expect(invoice.items.first.id, isNot(invoice.items.last.id));
    expect(invoice.items.first.toJson()['id'], invoice.items.first.id);
    expect(
      invoice.items.first.copyWith(quantity: 5).id,
      invoice.items.first.id,
    );

    // Un id déjà présent est relu tel quel (pas de régénération).
    const withId = '{"id": "item-42", "name": "Riz", "quantity": 1, "unitPrice": 100}';
    final reread = InvoiceItem.fromJson(
      jsonDecode(withId) as Map<String, dynamic>,
    );
    expect(reread.id, 'item-42');

    // Les anciens JSON restent lisibles par l'API historique.
    final raw = jsonDecode(legacyInvoices) as List;
    expect(raw, hasLength(1));
  });

  testWidgets('l’app s’ouvre sur un stockage ancien et garde le total arrondi',
      (tester) async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({
      Constants.invoicesKey: legacyInvoices,
      'products': jsonEncode([
        {
          'id': 'p1',
          'name': 'Ancien produit',
          'category': 'Catégorie',
          'imagePath': 'C:\\photos\\ancien.jpg',
        },
      ]),
      'history_client_names': <String>['Ancien Client'],
      'history_product_names': <String>['Riz'],
    });
    InvoiceRepository().resetForTests();
    HistoryService.resetCacheForTests();

    await tester.pumpWidget(const InvoiceApp());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'Admin');
    await tester.enterText(find.byType(TextFormField).at(1), '0000');
    await tester.tap(find.text('Se connecter'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Historique'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.textContaining(formatCurrency(1993)), findsWidgets);
    expect(find.textContaining('Ancien Client'), findsWidgets);
  });

  test('migration : chemins absolus copiés, fichiers disparus mis à null',
      () async {
    final temp = await Directory.systemTemp.createTemp('invoice_legacy_');
    addTearDown(() => temp.delete(recursive: true));

    final legacyImage = File('${temp.path}${Platform.pathSeparator}ancien.jpg');
    await legacyImage.writeAsBytes(<int>[9, 8, 7]);

    SharedPreferences.setMockInitialValues({
      'products': jsonEncode([
        {
          'id': 'p1',
          'name': 'Avec image',
          'category': 'Catégorie',
          'imagePath': legacyImage.path,
        },
        {
          'id': 'p2',
          'name': 'Sans fichier',
          'category': 'Catégorie',
          'imagePath': '${temp.path}${Platform.pathSeparator}absent.jpg',
        },
      ]),
    });

    final store = ProductImageStore(documentsDirectory: () async => temp);
    await store.init();

    final products = await ProductService().loadProducts();
    final withImage = products.firstWhere((p) => p.id == 'p1');
    final withoutFile = products.firstWhere((p) => p.id == 'p2');

    expect(withImage.imagePath, isNotNull);
    expect(withImage.imagePath, isNot(contains('/')));
    expect(withImage.imagePath, isNot(contains('\\')));
    final copied = File(
        '${temp.path}${Platform.pathSeparator}product_images'
        '${Platform.pathSeparator}${withImage.imagePath}');
    expect(await copied.exists(), isTrue);
    expect(await copied.readAsBytes(), <int>[9, 8, 7]);

    expect(withoutFile.imagePath, isNull);
    // Rien n'a été supprimé de l'ancien emplacement.
    expect(await legacyImage.exists(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ProductImageStore.migrationFlagKey), isTrue);

    // Migration unique : un second démarrage ne modifie plus rien.
    final before = withImage.imagePath;
    await store.init();
    final after = (await ProductService().loadProducts())
        .firstWhere((p) => p.id == 'p1')
        .imagePath;
    expect(after, before);
  });
}
