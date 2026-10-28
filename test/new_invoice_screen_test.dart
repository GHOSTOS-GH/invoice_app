// test/new_invoice_screen_test.dart
// Écran de création : suppression par glissement annulable, autocomplétion
// synchrone, dernier prix et brouillon sans « Client inconnu ».

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/new_invoice_screen.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/utils/constants.dart';
import 'package:invoice_app/utils/formatters.dart';

const String _draftWithThreeItems = '''
{
  "id": "draft",
  "clientName": "Client Test",
  "createdAt": "2026-10-01T10:00:00.000",
  "items": [
    {"name": "Article 1", "quantity": 1, "unitPrice": 1000},
    {"name": "Article 2", "quantity": 2, "unitPrice": 2000},
    {"name": "Article 3", "quantity": 3, "unitPrice": 1500}
  ],
  "status": "enCours"
}
''';

Future<void> _pumpNewInvoice(WidgetTester tester) async {
  // Le panneau d'ajout et l'état vide tiennent sur un écran de téléphone :
  // on donne au test une surface suffisante.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: NewInvoiceScreen(onInvoiceCreated: () {}),
    ),
  );
  await tester.pumpAndSettle();
}

Future<List<String>> _draftItemNames() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(Constants.draftInvoiceKey);
  if (raw == null) return const [];
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['items'] as List)
      .map((item) => (item as Map<String, dynamic>)['name'] as String)
      .toList();
}

/// Remise à zéro dans le corps du test : les futures du repository doivent
/// appartenir à la zone de test pour que les await se terminent.
void _resetData() {
  InvoiceRepository().resetForTests();
  HistoryService.resetCacheForTests();
}

Future<void> _swipeAway(WidgetTester tester, String article) async {
  await tester.drag(find.text(article), const Offset(-600, 0));
  await tester.pumpAndSettle();
}

void _expectOrder(WidgetTester tester, List<String> articles) {
  for (var i = 0; i < articles.length - 1; i++) {
    expect(
      tester.getTopLeft(find.text(articles[i])).dy,
      lessThan(tester.getTopLeft(find.text(articles[i + 1])).dy),
      reason: '"${articles[i]}" doit précéder "${articles[i + 1]}"',
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Création : suppression par swipe', () {
    testWidgets('supprimer le 2e garde les bons articles, Annuler le réinsère',
        (tester) async {
      _resetData();
      SharedPreferences.setMockInitialValues({
        Constants.draftInvoiceKey: _draftWithThreeItems,
      });
      await _pumpNewInvoice(tester);

      expect(find.text('Article 1'), findsOneWidget);
      expect(find.text('Article 2'), findsOneWidget);
      expect(find.text('Article 3'), findsOneWidget);

      await _swipeAway(tester, 'Article 2');

      expect(find.text('Article 2'), findsNothing);
      expect(find.text('Article 1'), findsOneWidget);
      expect(find.text('Article 3'), findsOneWidget);
      // Les bonnes valeurs restent attachées aux bonnes lignes.
      expect(find.text('1 × ${formatNumber(1000)} FCFA'), findsOneWidget);
      expect(find.text('3 × ${formatNumber(1500)} FCFA'), findsOneWidget);
      expect(find.text('Article supprimé'), findsOneWidget);
      _expectOrder(tester, const ['Article 1', 'Article 3']);
      expect(await _draftItemNames(), ['Article 1', 'Article 3']);

      await tester.tap(find.text('ANNULER'));
      await tester.pumpAndSettle();

      expect(find.text('Article 1'), findsOneWidget);
      expect(find.text('Article 2'), findsOneWidget);
      expect(find.text('Article 3'), findsOneWidget);
      _expectOrder(tester, const ['Article 1', 'Article 2', 'Article 3']);
      expect(find.text('2 × ${formatNumber(2000)} FCFA'), findsOneWidget);
      expect(await _draftItemNames(), ['Article 1', 'Article 2', 'Article 3']);
    });

    testWidgets('supprimer le 1er puis le dernier', (tester) async {
      _resetData();
      SharedPreferences.setMockInitialValues({
        Constants.draftInvoiceKey: _draftWithThreeItems,
      });
      await _pumpNewInvoice(tester);

      await _swipeAway(tester, 'Article 1');
      expect(find.text('Article 1'), findsNothing);
      _expectOrder(tester, const ['Article 2', 'Article 3']);

      await _swipeAway(tester, 'Article 3');
      expect(find.text('Article 3'), findsNothing);
      expect(find.text('Article 2'), findsOneWidget);
      expect(find.text('2 × ${formatNumber(2000)} FCFA'), findsOneWidget);
      expect(await _draftItemNames(), ['Article 2']);
    });

    testWidgets('supprimer tous les articles vide la liste', (tester) async {
      _resetData();
      SharedPreferences.setMockInitialValues({
        Constants.draftInvoiceKey: _draftWithThreeItems,
      });
      await _pumpNewInvoice(tester);

      await _swipeAway(tester, 'Article 1');
      await _swipeAway(tester, 'Article 2');
      await _swipeAway(tester, 'Article 3');

      expect(find.text('Aucun article'), findsOneWidget);
      expect(await _draftItemNames(), isEmpty);
    });
  });

  group('Autocomplétion et dernier prix', () {
    const products = '''
    [
      {"id": "p1", "name": "Riz parfumé", "category": "Céréales"},
      {"id": "p2", "name": "Huile rouge", "category": "Épicerie"}
    ]
    ''';

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'products': products,
        'history_client_names': <String>['Aïssatou Diop', 'Mamadou Diallo'],
      });
    });

    Future<void> seedInvoices() async {
      await InvoiceRepository().replaceAll([
        Invoice(
          id: 'inv-mamadou',
          clientName: 'Mamadou Diallo',
          createdAt: DateTime(2026, 10, 12, 9),
          items: [
            InvoiceItem(id: 'a', name: 'Riz parfumé', quantity: 1, unitPrice: 1200),
            InvoiceItem(id: 'b', name: 'Huile rouge', quantity: 1, unitPrice: 2500),
          ],
        ),
        Invoice(
          id: 'inv-aissatou',
          clientName: 'Aïssatou Diop',
          createdAt: DateTime(2026, 10, 5, 9),
          items: [
            InvoiceItem(id: 'c', name: 'Riz parfumé', quantity: 1, unitPrice: 900),
          ],
        ),
      ]);
    }

    Future<void> openAddPanel(WidgetTester tester) async {
      await tester.tap(find.text('Ajouter un article'));
      await tester.pumpAndSettle();
    }

    Future<void> selectProduct(WidgetTester tester, String name) async {
      await tester.tap(find.text('Appuyez pour choisir un produit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    TextField priceField(WidgetTester tester) => tester.widget<TextField>(
          find.widgetWithText(TextField, 'Prix unitaire (FCFA)'),
        );

    testWidgets('taper "mam" propose le client sans afficher de prix',
        (tester) async {
      _resetData();
      await seedInvoices();
      await _pumpNewInvoice(tester);
      await openAddPanel(tester);
      await selectProduct(tester, 'Riz parfumé');

      expect(find.textContaining('Dernier prix'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nom du client (optionnel)'),
        'mam',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('client-option-Mamadou Diallo')),
        findsOneWidget,
      );
      // Un seul client connu commence par « mam » : aide discrète proposée.
      expect(
        find.text('Client existant : Mamadou Diallo — Utiliser'),
        findsOneWidget,
      );
      // Aucun encart de prix tant qu'aucun client n'est résolu.
      expect(find.textContaining('Dernier prix'), findsNothing);
      expect(priceField(tester).controller!.text, isEmpty);
    });

    testWidgets('choisir la suggestion ferme la liste, pré-remplit le prix '
        'et affiche prix + date', (tester) async {
      _resetData();
      await seedInvoices();
      await _pumpNewInvoice(tester);
      await openAddPanel(tester);
      await selectProduct(tester, 'Riz parfumé');

      await tester.enterText(
        find.widgetWithText(TextField, 'Nom du client (optionnel)'),
        'mam',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('client-option-Mamadou Diallo')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('client-option-Mamadou Diallo')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'Nom du client (optionnel)'))
            .controller!
            .text,
        'Mamadou Diallo',
      );
      expect(find.textContaining('Dernier prix pour Mamadou Diallo'), findsOneWidget);
      expect(find.textContaining('12/10/2026'), findsOneWidget);
      expect(find.text('Utiliser ce prix'), findsOneWidget);
      expect(priceField(tester).controller!.text, '1200');

      // Perdre puis reprendre le focus ne rouvre pas la liste.
      await tester.tap(find.widgetWithText(TextField, 'Quantité *'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextField, 'Nom du client (optionnel)'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('client-option-Mamadou Diallo')),
        findsNothing,
      );
    });

    testWidgets('"aissatou" trouve « Aïssatou Diop »', (tester) async {
      _resetData();
      await seedInvoices();
      await _pumpNewInvoice(tester);
      await openAddPanel(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nom du client (optionnel)'),
        'aissatou',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('client-option-Aïssatou Diop')),
        findsOneWidget,
      );
    });

    testWidgets('modifier le prix puis changer de produit remet le '
        'pré-remplissage', (tester) async {
      _resetData();
      await seedInvoices();
      await _pumpNewInvoice(tester);
      await openAddPanel(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nom du client (optionnel)'),
        'Mamadou Diallo',
      );
      await tester.pumpAndSettle();

      await selectProduct(tester, 'Riz parfumé');
      expect(priceField(tester).controller!.text, '1200');

      await tester.enterText(
        find.widgetWithText(TextField, 'Prix unitaire (FCFA)'),
        '500',
      );
      await tester.pumpAndSettle();
      expect(priceField(tester).controller!.text, '500');

      await tester.tap(find.text('Riz parfumé'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huile rouge'));
      await tester.pumpAndSettle();

      expect(priceField(tester).controller!.text, '2500');
      expect(find.textContaining('Dernier prix pour Mamadou Diallo'), findsOneWidget);
    });
  });
}
