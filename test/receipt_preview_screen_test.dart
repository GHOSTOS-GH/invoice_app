// test/receipt_preview_screen_test.dart
// Scénario du bug critique : des paramètres de reçu ont été sauvegardés
// (avec logo activé), puis on ouvre l'aperçu du reçu depuis
// « Partager → Reçu thermique ». L'écran doit s'ouvrir instantanément,
// sans boucle infinie (_reload → _loadContent → loadSettings → notify)
// ni freeze (ANR). Sans le correctif, ce test ne termine jamais (timeout).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/receipt_settings.dart';
import 'package:invoice_app/screens/receipt_preview_screen.dart';
import 'package:invoice_app/services/receipt_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      "l'aperçu du reçu s'ouvre sans freeze (logo activé + paramètres "
      'sauvegardés)', (WidgetTester tester) async {
    // runAsync : vraie exécution asynchrone (SharedPreferences, lecture
    // du fichier logo, isolate compute() pour le logo).
    await tester.runAsync(() async {
      // Logo réel dans un fichier temporaire.
      final dir = Directory.systemTemp.createTempSync('receipt_preview_test');
      final logoFile = File('${dir.path}/receipt_logo.png');
      final src = img.Image(width: 60, height: 40);
      img.fill(src, color: img.ColorRgb8(180, 60, 60));
      logoFile.writeAsBytesSync(img.encodePng(src));

      // Paramètres du reçu déjà sauvegardés, avec logo activé
      // (équivalent : onglet Réglages → Reçu, puis ouverture de l'aperçu).
      SharedPreferences.setMockInitialValues({});
      await ReceiptSettingsService().saveSettings(ReceiptSettings(
        shopName: 'Boutique Test',
        logoPath: logoFile.path,
        showLogo: true,
      ));

      final invoice = Invoice(
        id: '20260815123456',
        clientName: 'Client Test',
        createdAt: DateTime(2026, 8, 15, 14, 30),
        items: const [
          InvoiceItem(name: 'Article A', quantity: 1, unitPrice: 1000),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: ReceiptPreviewScreen(invoice: invoice),
      ));
      await tester.pump();

      // Attend que le contenu du reçu soit rendu. Si la boucle infinie
      // était toujours là, aucun rendu n'arriverait et le délai écoulerait
      // le budget du test (échec net), exactement comme l'ANR en réel.
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var rendered = false;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.text('BOUTIQUE TEST').evaluate().isNotEmpty) {
          rendered = true;
          break;
        }
      }

      expect(rendered, isTrue,
          reason: "le reçu doit s'afficher (nom de la boutique en tête)");
      expect(tester.takeException(), isNull);

      dir.deleteSync(recursive: true);
    });
  });
}
