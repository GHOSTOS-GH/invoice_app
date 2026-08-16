// Test de fumée : vérifie le chargement de l'app, la connexion admin
// et la navigation entre les 4 onglets (Facture, Historique, Stats, Paramètres).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/main.dart';

void main() {
  testWidgets('InvoiceApp loads, login and navigation work', (WidgetTester tester) async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const InvoiceApp());
    await tester.pump();

    // Écran de connexion affiché (non authentifié)
    expect(find.text('Accès Administrateur'), findsOneWidget);

    // Connexion avec les identifiants admin
    await tester.enterText(find.byType(TextFormField).at(0), 'Admin');
    await tester.enterText(find.byType(TextFormField).at(1), '0000');
    await tester.tap(find.text('Se connecter'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // La barre de navigation est visible
    expect(find.byType(NavigationBar), findsOneWidget);

    // Onglet Stats (état vide car aucune facture)
    await tester.tap(find.text('Stats'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Aucune donnée pour le moment'), findsOneWidget);

    // Onglet Historique
    await tester.tap(find.text('Historique'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Historique'), findsWidgets);

    // Onglet Paramètres
    await tester.tap(find.text('Paramètres'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Paramètres'), findsWidgets);

    // Onglet Facture (accueil)
    await tester.tap(find.text('Facture'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Nouvelle Facture'), findsOneWidget);
  });
}
