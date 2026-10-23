// test/stats_screen_test.dart
// Les statistiques écoutent le repository : créer une facture met à jour
// l'écran sans appuyer sur « Actualiser ».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/stats_screen.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/utils/formatters.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('une nouvelle facture met à jour les stats sans actualiser',
      (tester) async {
    // Dans le corps du test : les futures du repository doivent appartenir à
    // la zone de test pour que les await se terminent.
    InvoiceRepository().resetForTests();
    await initializeDateFormatting('fr_FR', null);
    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    // Pas de pumpAndSettle : le squelette de chargement a une animation
    // infinie tant que le repository n'a pas répondu.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Aucune donnée pour le moment'), findsOneWidget);

    await InvoiceRepository().add(
      Invoice(
        id: 'inv-stats',
        clientName: 'Client Test',
        createdAt: DateTime.now(),
        items: [
          InvoiceItem(id: 's1', name: 'Article', quantity: 2, unitPrice: 1500),
        ],
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Aucune donnée pour le moment'), findsNothing);
    expect(find.text(formatCurrency(3000)), findsWidgets);
  });
}
