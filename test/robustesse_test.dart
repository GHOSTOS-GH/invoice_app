// test/robustesse_test.dart
// Robustesse : volumes importants, saisies extrêmes, contraintes d'affichage.
// Chaque test protège un scénario limite validé pendant la recette.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/history_screen.dart';
import 'package:invoice_app/screens/new_invoice_screen.dart';
import 'package:invoice_app/screens/stats_screen.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/pdf/invoice_pdf_builder.dart';
import 'package:invoice_app/services/storage_service.dart';
import 'package:invoice_app/theme/app_theme.dart';
import 'package:invoice_app/utils/constants.dart';
import 'package:invoice_app/utils/formatters.dart';

// ---------------------------------------------------------------------------
// Outils
// ---------------------------------------------------------------------------

void _resetData() {
  InvoiceRepository().resetForTests();
  HistoryService.resetCacheForTests();
}

void _setSurface(WidgetTester tester, {Size size = const Size(900, 1800)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Laisse tourner les animations sans `pumpAndSettle` (squelettes, graphiques).
Future<void> _pumpFrames(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// 1 000 factures réparties sur une année, deux articles chacune.
List<Invoice> _manyInvoices(int count) {
  final base = DateTime(2026, 10, 1, 12);
  return List<Invoice>.generate(count, (index) {
    final number = index + 1;
    return Invoice(
      id: '${1700000000000 + index}',
      clientName: 'client $number',
      createdAt: base.subtract(Duration(days: index % 365)),
      status: InvoiceStatus.values[index % InvoiceStatus.values.length],
      items: [
        InvoiceItem(
          id: 'a-$index',
          name: 'Article $number',
          quantity: index % 5 + 1,
          unitPrice: 1000 + index,
        ),
        InvoiceItem(
          id: 'b-$index',
          name: 'Autre $number',
          quantity: 2,
          unitPrice: 500,
        ),
      ],
    );
  });
}

/// Compte les pages d'un PDF produit par le moteur de l'application.
int _pdfPageCount(List<int> pdf) {
  final text = String.fromCharCodes(pdf);
  return RegExp(r'/Type\s*/Page\b').allMatches(text).length;
}

/// Noms des articles du brouillon persisté (SharedPreferences).
Future<List<String>> _draftItemNames() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(Constants.draftInvoiceKey);
  if (raw == null) return const [];
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['items'] as List)
      .map((item) => (item as Map<String, dynamic>)['name'] as String)
      .toList();
}

/// 3 articles de brouillon (tous entiers FCFA).
const String _draftWithThreeItems = '''
{
  "id": "draft",
  "clientName": "Client Rotation",
  "createdAt": "2026-10-01T10:00:00.000",
  "items": [
    {"name": "Article 1", "quantity": 1, "unitPrice": 1000},
    {"name": "Article 2", "quantity": 2, "unitPrice": 2000},
    {"name": "Article 3", "quantity": 3, "unitPrice": 1500}
  ],
  "status": "enCours"
}
''';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Robustesse', () {
    test('1 000 factures : chargement et filtrage en moins de 2 s', () async {
      _resetData();
      final invoices = _manyInvoices(1000);

      final watch = Stopwatch()..start();
      // Persistance puis rechargement réels (SharedPreferences).
      await StorageService().saveInvoices(invoices);
      final loaded = await StorageService().loadInvoices();
      await InvoiceRepository().replaceAll(loaded);
      // Filtrage équivalent à l'historique : statut + tri par date décroissante.
      final filtered = loaded
          .where((invoice) => invoice.status == InvoiceStatus.livree)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      watch.stop();

      expect(loaded, hasLength(1000));
      expect(filtered, isNotEmpty);
      expect(InvoiceRepository().invoices, hasLength(1000));
      expect(
        watch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'chargement + filtrage de 1 000 factures : '
            '${watch.elapsedMilliseconds} ms',
      );
    });

    testWidgets('1 000 factures : recherche « client 500 » en moins de 500 ms',
        (tester) async {
      _resetData();
      _setSurface(tester);
      await InvoiceRepository().replaceAll(_manyInvoices(1000));

      await tester.pumpWidget(
        MaterialApp(home: HistoryScreen(onInvoiceUpdated: () {})),
      );
      await _pumpFrames(tester);

      final watch = Stopwatch()..start();
      await tester.enterText(find.byType(TextField).first, 'client 500');
      // Le champ applique un anti-rebond de 250 ms.
      await tester.pump(const Duration(milliseconds: 300));
      await _pumpFrames(tester, frames: 4);
      watch.stop();

      // Le champ de recherche contient aussi le texte : au moins une carte.
      expect(find.text('client 500'), findsWidgets);
      expect(find.text('client 499'), findsNothing);
      expect(
        watch.elapsedMilliseconds,
        lessThan(500),
        reason:
            'recherche sur 1 000 factures : ${watch.elapsedMilliseconds} ms',
      );
    });

    testWidgets('liste vide : toutes les vues ne crashent pas', (tester) async {
      _resetData();
      _setSurface(tester);

      // Historique vide.
      await tester.pumpWidget(
        MaterialApp(home: HistoryScreen(onInvoiceUpdated: () {})),
      );
      await _pumpFrames(tester);
      expect(find.text('Aucune facture'), findsOneWidget);

      // Statistiques vides.
      await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Aucune donnée pour le moment'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    test('nom client de 200 caractères : InvoiceItem accepté et formaté', () {
      final longClientName = 'C' * 200;
      final longItemName = 'A' * 200;

      final invoice = Invoice(
        id: '1700000000200',
        clientName: longClientName,
        createdAt: DateTime(2026, 10, 12, 9, 30),
        items: [
          InvoiceItem(
            id: 'long-1',
            name: longItemName,
            quantity: 2,
            unitPrice: 1500,
          ),
        ],
      );

      expect(invoice.clientName.length, 200);
      expect(invoice.items.single.name.length, 200);
      expect(invoice.payableTotal, 3000);

      // Le JSON conserve les libellés intacts (aucune troncature silencieuse).
      final decoded = Invoice.fromJson(
        jsonDecode(jsonEncode(invoice.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.clientName, longClientName);
      expect(decoded.items.single.name, longItemName);
      expect(decoded.payableTotal, 3000);

      // Les montants restent des entiers sans décimale à l'affichage.
      expect(formatCurrency(decoded.payableTotal), '3\u{00A0}000 FCFA');
      expect(formatCurrency(decoded.payableTotal), isNot(contains('.')));
      expect(formatCurrency(decoded.payableTotal), isNot(contains(',')));
    });

    test('article de 150 caractères : PDF généré sans exception', () async {
      final invoice = Invoice(
        id: '1700000000150',
        clientName: 'Client Libellé Long',
        createdAt: DateTime(2026, 10, 12, 9, 30),
        items: [
          InvoiceItem(
            id: 'long-name',
            name: 'Article ${'très long libellé ' * 8}'.trim(),
            quantity: 3,
            unitPrice: 2500,
          ),
        ],
      );
      expect(invoice.items.single.name.length, greaterThanOrEqualTo(150));

      final pdf = await const InvoicePdfBuilder().build(invoice);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(1000));
    });

    test('quantité 999 999 et prix 99 999 999 : pas de débordement int',
        () async {
      final invoice = Invoice(
        id: '1700000000999',
        clientName: 'Client Extrême',
        createdAt: DateTime(2026, 10, 12, 9, 30),
        items: [
          InvoiceItem(
            id: 'max-1',
            name: 'Gros volume',
            quantity: 999999,
            unitPrice: 99999999,
          ),
          InvoiceItem(
            id: 'max-2',
            name: 'Complément',
            quantity: 1,
            unitPrice: 2500,
          ),
        ],
      );

      const expectedLine = 999999 * 99999999; // 99 999 899 000 001
      expect(invoice.items.first.subtotal, expectedLine);
      expect(invoice.total, expectedLine + 2500);
      expect(invoice.payableTotal, expectedLine + 2500);
      // Les valeurs restent dans l'intervalle des entiers 64 bits signés.
      expect(invoice.total, lessThan(9223372036854775807));
      expect(invoice.total, greaterThan(0));

      // Aucune écriture scientifique ni décimale à l'affichage ou en CSV.
      final formatted = formatNumber(invoice.payableTotal);
      expect(formatted, isNot(contains('e')));
      expect(formatted, isNot(contains('.')));
      expect(formatted, isNot(contains(',')));

      // Le PDF encaisse le montant sans exception.
      final pdf = await const InvoicePdfBuilder().build(invoice);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('facture à 80 articles : PDF multi-pages, totaux corrects', () async {
      final items = List<InvoiceItem>.generate(
        80,
        (index) => InvoiceItem(
          id: 'item-$index',
          name: 'Article ${index + 1} avec un libellé un peu long',
          quantity: index % 5 + 1,
          unitPrice: 1000 + index * 75,
        ),
      );
      final invoice = Invoice(
        id: '1700000000080',
        clientName: 'Client Volume',
        createdAt: DateTime(2026, 10, 12, 9, 30),
        items: items,
        discount: 5000,
        taxRate: 10,
      );

      final expectedSubtotal =
          items.fold<int>(0, (sum, item) => sum + item.subtotal);
      expect(invoice.subtotal, expectedSubtotal);
      expect(
        invoice.payableTotal,
        expectedSubtotal -
            5000 +
            ((expectedSubtotal - 5000) * 10 / 100).round(),
      );

      final pdf = await const InvoicePdfBuilder().build(invoice);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(_pdfPageCount(pdf), greaterThan(1));
    });

    testWidgets('rotation d’écran : NewInvoiceScreen conserve son brouillon',
        (tester) async {
      _resetData();
      SharedPreferences.setMockInitialValues({
        Constants.draftInvoiceKey: _draftWithThreeItems,
      });

      // Portrait.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: NewInvoiceScreen(onInvoiceCreated: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Article 1'), findsOneWidget);
      expect(find.text('Article 2'), findsOneWidget);
      expect(find.text('Article 3'), findsOneWidget);
      expect(await _draftItemNames(), ['Article 1', 'Article 2', 'Article 3']);

      // Paysage : le brouillon garde ses trois articles (la liste est
      // paresseuse, on contrôle le brouillon persisté et le premier article).
      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpAndSettle();
      expect(find.text('Article 1'), findsOneWidget);
      expect(await _draftItemNames(), ['Article 1', 'Article 2', 'Article 3']);

      // Retour au portrait : toujours aucun article perdu.
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(find.text('Article 1'), findsOneWidget);
      expect(find.text('Article 2'), findsOneWidget);
      expect(find.text('Article 3'), findsOneWidget);
      expect(await _draftItemNames(), ['Article 1', 'Article 2', 'Article 3']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('textScaler 1.3 : HistoryScreen aucun overflow',
        (tester) async {
      _resetData();
      _setSurface(tester, size: const Size(400, 800));
      await InvoiceRepository().replaceAll(_manyInvoices(5));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: HistoryScreen(onInvoiceUpdated: () {}),
        ),
      );
      await _pumpFrames(tester, frames: 12);

      expect(find.text('client 1'), findsOneWidget);
      // Un dépassement de mise en page serait remonté comme exception.
      expect(tester.takeException(), isNull);
    });

    testWidgets('mode sombre : StatsScreen se construit sans exception',
        (tester) async {
      _resetData();
      _setSurface(tester);
      await InvoiceRepository().replaceAll(_manyInvoices(6));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const StatsScreen(),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      // Période « Tout » : les factures de test couvrent toute l'année.
      await tester.tap(find.text('Tout'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      final total = InvoiceRepository()
          .invoices
          .fold<int>(0, (sum, invoice) => sum + invoice.payableTotal);
      expect(tester.takeException(), isNull);
      expect(find.text(formatCurrency(total)), findsWidgets);
    });
  });
}
