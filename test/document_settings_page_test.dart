// test/document_settings_page_test.dart
// Page « Facture (PDF & images) » : aperçu debouncé, enregistrement immédiat,
// copie depuis le reçu, réinitialisation confirmée.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/receipt_settings.dart';
import 'package:invoice_app/screens/settings/document_page.dart';
import 'package:invoice_app/services/document_settings_service.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_image_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/theme/app_theme.dart';
import 'package:invoice_app/utils/constants.dart';

class _FakeRenderer implements InvoiceImageRenderer {
  int calls = 0;
  DocumentSettings? lastSettings;

  static final Uint8List _png = Uint8List.fromList(
    img.encodePng(img.Image(width: 30, height: 42)),
  );

  @override
  Future<InvoiceImageResult> render(
    Invoice invoice, {
    DocumentSettings? settings,
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output = InvoiceOutputFormat.png,
    int? jpgQuality,
  }) async {
    calls++;
    lastSettings = settings;
    return InvoiceImageResult(
      pages: [_png],
      format: imageFormat ?? DocumentImageFormat.a4,
      forcedA4: false,
    );
  }
}

const String _receiptJson = '''
{"shopName":"Boutique Konté","shopAddress":"Marché Sandaga",
 "shopPhone":"77 123 45 67","shopNinea":"NINEA 987"}
''';

Future<void> _pump(WidgetTester tester, _FakeRenderer renderer) async {
  tester.view.physicalSize = const Size(500, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: DocumentSettingsPage(imageService: renderer),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Map<String, dynamic>> _stored() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(Constants.documentSettingsKey);
  return jsonDecode(raw!) as Map<String, dynamic>;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      Constants.receiptSettingsKey: _receiptJson,
    });
    InvoiceRepository().resetForTests();
    HistoryService.resetCacheForTests();
    DocumentSettingsService.settingsNotifier.value =
        DocumentSettings.defaults();
  });

  testWidgets('affiche l’aperçu et les six sections', (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer);

    expect(renderer.calls, 1);
    expect(find.text('Aperçu en direct'), findsOneWidget);
    for (final title in [
      'Entreprise',
      'Éléments affichés',
      'Style',
      'Paiement & QR',
      'Pied de page',
      'Images',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // Les informations du reçu ont prérempli l'entreprise.
    expect(find.text('Boutique Konté'), findsOneWidget);
  });

  testWidgets('un interrupteur est enregistré immédiatement', (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer);

    await tester.tap(find.text('Éléments affichés'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Badge de statut'));
    await tester.pump();

    expect((await _stored())['showStatusBadge'], isTrue);
    expect(
      DocumentSettingsService.settingsNotifier.value.showStatusBadge,
      isTrue,
    );
  });

  testWidgets('l’aperçu est régénéré après 400 ms, une seule fois',
      (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer);
    expect(renderer.calls, 1);

    await tester.tap(find.text('Éléments affichés'));
    await tester.pumpAndSettle();

    // Trois changements rapprochés : un seul nouvel aperçu.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Badge de statut'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Notes'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Prix unitaire'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(renderer.calls, 1);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(renderer.calls, 2);
    expect(renderer.lastSettings?.showNotes, isFalse);
  });

  testWidgets('le texte saisi est enregistré', (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nom de l’entreprise'),
      'Konté Business',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect((await _stored())['businessName'], 'Konté Business');
  });

  testWidgets('copie depuis les infos du reçu', (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer);

    // Un réglage déjà personnalisé ne doit pas être écrasé par du vide.
    await tester.tap(find.text('Copier depuis les infos du reçu'));
    await tester.pumpAndSettle();

    final stored = await _stored();
    expect(stored['businessName'], 'Boutique Konté');
    expect(stored['businessPhone'], '77 123 45 67');
    expect(stored['businessRegistration'], 'NINEA 987');
    expect(find.text('Informations du reçu copiées'), findsOneWidget);
  });

  testWidgets('réinitialisation après confirmation', (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer);

    await tester.tap(find.text('Éléments affichés'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Badge de statut'));
    await tester.pump();
    expect((await _stored())['showStatusBadge'], isTrue);

    await tester.tap(find.text('Réinitialiser aux valeurs par défaut'));
    await tester.pumpAndSettle();

    // Sans confirmation, rien ne change.
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect((await _stored())['showStatusBadge'], isTrue);

    await tester.tap(find.text('Réinitialiser aux valeurs par défaut'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Réinitialiser'));
    await tester.pumpAndSettle();

    final stored = await _stored();
    expect(stored['showStatusBadge'], isFalse);
    expect(stored['businessName'], 'Facturier Konté Business Services');
    expect(DocumentSettingsService.settingsNotifier.value,
        DocumentSettings.defaults());
  });

  testWidgets('le modèle et la couleur sont enregistrés', (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer);

    await tester.tap(find.text('Style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classique'));
    await tester.pump();

    expect((await _stored())['template'], 'classic');
    expect(
      DocumentSettingsService.settingsNotifier.value.template,
      DocumentTemplate.classic,
    );
    expect(ReceiptSettings.defaults().shopName, '');
  });
}
