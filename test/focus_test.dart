// test/focus_test.dart
// Focus clavier : il ne doit jamais se rouvrir tout seul après un changement
// de page (retour d'un détail, changement d'onglet). Les opérations sur le
// repository restent dans le corps des tests, jamais dans setUp.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/main.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/history_screen.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/theme/app_theme.dart';
import 'package:invoice_app/utils/focus_observer.dart';

Invoice _invoice() => Invoice(
      id: '1700000000000',
      clientName: 'Aïssatou Diop',
      createdAt: DateTime(2026, 10, 12, 9, 30),
      items: [
        InvoiceItem(id: 'i1', name: 'Riz parfumé', quantity: 2, unitPrice: 1500),
      ],
    );

void _resetData() {
  InvoiceRepository().resetForTests();
  HistoryService.resetCacheForTests();
}

void _setSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Aucun champ de saisie ne doit garder le focus (clavier fermé).
bool _hasFocusedTextField(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .any((editable) => editable.focusNode.hasFocus);

/// Avance de quelques frames : pas de pumpAndSettle sur les écrans qui
/// contiennent SkeletonLoader ou fl_chart (animations sans fin).
Future<void> _pumpFrames(
  WidgetTester tester, {
  int count = 10,
  int milliseconds = 60,
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(Duration(milliseconds: milliseconds));
  }
}

Finder _navLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

Finder _historySearchField() => find
    .descendant(
      of: find.byType(HistoryScreen),
      matching: find.byType(TextField),
    )
    .first;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  testWidgets('l’observateur défocalise le champ actif à chaque page',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        navigatorObservers: [UnfocusNavigatorObserver()],
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final focusNode = FocusNode();
              addTearDown(focusNode.dispose);
              return Column(
                children: [
                  TextField(focusNode: focusNode),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (routeContext) => Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () => Navigator.pop(routeContext),
                              child: const Text('Retour'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Ouvrir'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(_hasFocusedTextField(tester), isTrue);

    // Page poussée : le champ d'origine perd le focus, même sans unfocus
    // explicite de l'écran.
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(_hasFocusedTextField(tester), isFalse);

    // Retour : le Navigator restaure normalement le focus, l'observateur
    // l'annule après la frame.
    await tester.tap(find.text('Retour'));
    await tester.pumpAndSettle();
    expect(_hasFocusedTextField(tester), isFalse);
  });

  testWidgets(
      'Historique : le focus de la recherche ne revient pas au retour du détail',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    _resetData();
    await InvoiceRepository().replaceAll([_invoice()]);
    _setSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        navigatorObservers: [UnfocusNavigatorObserver()],
        home: HistoryScreen(onInvoiceUpdated: () {}),
      ),
    );
    await _pumpFrames(tester);

    final search = _historySearchField();
    await tester.tap(search);
    await tester.pump();
    expect(_hasFocusedTextField(tester), isTrue);

    await tester.tap(find.text('Aïssatou Diop'));
    await _pumpFrames(tester);
    expect(find.byTooltip('Modifier'), findsOneWidget, reason: 'détail ouvert');
    expect(_hasFocusedTextField(tester), isFalse);

    await tester.tap(find.byType(BackButton));
    await _pumpFrames(tester);

    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(_hasFocusedTextField(tester), isFalse);
  });

  testWidgets(
      'InvoiceApp : Stats → Historique → détail → retour sans clavier',
      (tester) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    SharedPreferences.setMockInitialValues({'last_login_date': today});
    _resetData();
    await InvoiceRepository().replaceAll([_invoice()]);
    _setSurface(tester);

    await tester.pumpWidget(const InvoiceApp());
    await _pumpFrames(tester);

    await tester.tap(_navLabel('Stats'));
    await _pumpFrames(tester);

    await tester.tap(_navLabel('Historique'));
    await _pumpFrames(tester, count: 11);

    final search = _historySearchField();
    await tester.tap(search);
    await tester.pump();
    expect(_hasFocusedTextField(tester), isTrue);

    await tester.tap(find.text('Aïssatou Diop'));
    await _pumpFrames(tester);
    expect(find.byTooltip('Modifier'), findsOneWidget, reason: 'détail ouvert');

    await tester.tap(find.byType(BackButton));
    await _pumpFrames(tester);

    expect(_hasFocusedTextField(tester), isFalse);
  });
}
