// test/invoice_detail_screen_test.dart
// Édition du détail : une suppression n'altère pas les autres saisies, le
// total suit les brouillons, « Annuler » restaure tout et l'archivage ne
// persiste que le statut.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/invoice_detail_screen.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/utils/formatters.dart';

const _products = '''
[
  {"id": "p1", "name": "Riz parfumé", "category": "Céréales"}
]
''';

Invoice _invoiceTemplate({
  String id = 'inv-1',
  String clientName = 'Client Test',
  DateTime? createdAt,
  int firstQuantity = 1,
}) =>
    Invoice(
      id: id,
      clientName: clientName,
      createdAt: createdAt ?? DateTime(2026, 10, 12, 10),
      items: [
        InvoiceItem(
          id: 'i1',
          name: 'Article 1',
          quantity: firstQuantity,
          unitPrice: 1000,
        ),
        InvoiceItem(id: 'i2', name: 'Article 2', quantity: 2, unitPrice: 2000),
        InvoiceItem(id: 'i3', name: 'Article 3', quantity: 3, unitPrice: 1500),
      ],
    );

/// Remise à zéro dans le corps du test : les futures du repository doivent
/// appartenir à la zone de test pour que les await se terminent.
void _resetData() {
  InvoiceRepository().resetForTests();
  HistoryService.resetCacheForTests();
}

/// Surface assez haute pour que toutes les lignes et les boutons soient
/// visibles (l'écran est défilant sur un vrai téléphone).
void _setSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<Invoice> _pumpDetail(WidgetTester tester, Invoice invoice) async {
  _setSurface(tester);
  await InvoiceRepository().replaceAll([invoice]);
  await tester.pumpWidget(
    MaterialApp(
      home: InvoiceDetailScreen(invoice: invoice, onInvoiceUpdated: () {}),
    ),
  );
  await tester.pumpAndSettle();
  return invoice;
}

Future<void> _enterEditMode(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Modifier'));
  await tester.pumpAndSettle();
}

Finder _quantityFields() => find.widgetWithText(TextField, 'Quantité');

String _fieldText(WidgetTester tester, Finder finder) =>
    tester.widget<TextField>(finder).controller!.text;

Future<void> _deleteLine(WidgetTester tester, int index) async {
  await tester.tap(find.byTooltip('Supprimer').at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'products': _products});
  });

  testWidgets('modifier une ligne puis supprimer la 1re conserve la saisie',
      (tester) async {
    _resetData();
    final invoice = await _pumpDetail(tester, _invoiceTemplate());
    await _enterEditMode(tester);

    // Saisie de la ligne 3, sans aucune validation explicite.
    await tester.enterText(_quantityFields().at(2), '7');
    await tester.pump();

    await _deleteLine(tester, 0);

    expect(find.text('Article 1'), findsNothing);
    expect(_quantityFields(), findsNWidgets(2));
    // La ligne 3 est devenue la 2e : sa saisie est intacte.
    expect(_fieldText(tester, _quantityFields().at(1)), '7');
    expect(_fieldText(tester, _quantityFields().at(0)), '2');

    // Le total suit les brouillons en direct : 2×2000 + 7×1500.
    expect(find.text(formatCurrency(14500)), findsOneWidget);
    expect(invoice.items.length, 3);
  });

  testWidgets('modifier une ligne puis Enregistrer persiste la valeur',
      (tester) async {
    _resetData();
    await _pumpDetail(tester, _invoiceTemplate());
    await _enterEditMode(tester);

    await tester.enterText(_quantityFields().at(0), '4');
    await tester.pump();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();

    final stored = InvoiceRepository().invoices.single;
    expect(stored.items.first.quantity, 4);
    expect(stored.payableTotal, 4 * 1000 + 2 * 2000 + 3 * 1500);
    expect(find.text('Facture mise à jour'), findsOneWidget);
  });

  testWidgets('Annuler après suppression d’une ligne restaure les articles',
      (tester) async {
    _resetData();
    await _pumpDetail(tester, _invoiceTemplate());
    await _enterEditMode(tester);

    await _deleteLine(tester, 0);
    expect(find.text('Article 1'), findsNothing);

    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();

    expect(find.text('Article 1'), findsOneWidget);
    expect(find.text('Article 2'), findsOneWidget);
    expect(find.text('Article 3'), findsOneWidget);
    expect(InvoiceRepository().invoices.single.items.length, 3);
  });

  testWidgets('Enregistrer refuse une ligne à quantité 0 et affiche l’erreur',
      (tester) async {
    _resetData();
    await _pumpDetail(tester, _invoiceTemplate());
    await _enterEditMode(tester);

    await tester.enterText(_quantityFields().at(0), '0');
    await tester.pump();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('Quantité obligatoire (entier supérieur à 0)'), findsOneWidget);
    // Rien n'a été enregistré.
    expect(InvoiceRepository().invoices.single.items.first.quantity, 1);
    // On reste en édition.
    expect(find.byTooltip('Enregistrer'), findsOneWidget);
  });

  testWidgets('archiver n’enregistre pas les modifications non sauvegardées',
      (tester) async {
    _resetData();
    await _pumpDetail(tester, _invoiceTemplate());
    await _enterEditMode(tester);

    await tester.enterText(_quantityFields().at(0), '9');
    await tester.pump();

    await tester.tap(find.byTooltip('Archiver'));
    await tester.pumpAndSettle();

    final stored = InvoiceRepository().invoices.single;
    expect(stored.status, InvoiceStatus.archivee);
    // La quantité saisie n'est pas partie avec l'archivage.
    expect(stored.items.first.quantity, 1);
  });

  testWidgets('le dernier prix du panneau d’ajout exclut la facture en cours',
      (tester) async {
    _resetData();
    _setSurface(tester);
    final current = _invoiceTemplate(id: 'inv-current');
    final older = Invoice(
      id: 'inv-old',
      clientName: 'Client Test',
      createdAt: DateTime(2026, 9, 1, 8),
      items: [
        InvoiceItem(id: 'old', name: 'Riz parfumé', quantity: 1, unitPrice: 1200),
      ],
    );
    await InvoiceRepository().replaceAll([older, current]);
    await tester.pumpWidget(
      MaterialApp(
        home: InvoiceDetailScreen(invoice: current, onInvoiceUpdated: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await _enterEditMode(tester);

    await tester.tap(find.text('Ajouter un article'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appuyez pour choisir un produit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riz parfumé'));
    await tester.pumpAndSettle();

    // La facture en cours contient 'Riz parfumé' mais elle est exclue :
    // le dernier prix connu est celui de la facture plus ancienne.
    expect(find.textContaining(formatCurrency(1200)), findsOneWidget);
    final priceInput = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Prix unitaire (FCFA)'),
    );
    expect(priceInput.controller!.text, '1200');
  });
}
