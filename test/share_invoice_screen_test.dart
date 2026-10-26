// test/share_invoice_screen_test.dart
// Écran « Partager la facture » : aperçu réel, progression, sélecteurs de
// modèle / format (sans toucher aux réglages), erreur et « Réessayer ».

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/share_invoice_screen.dart';
import 'package:invoice_app/services/invoice_image_service.dart';
import 'package:invoice_app/services/pdf_service.dart';

/// Faux moteur d'images : renvoie de petites images valides, ou échoue.
class _FakeRenderer implements InvoiceImageRenderer {
  _FakeRenderer({this.failing = false, this.pageCount = 1, this.forcedA4 = false});

  bool failing;
  final int pageCount;
  final bool forcedA4;

  int calls = 0;
  DocumentTemplate? lastTemplate;
  DocumentImageFormat? lastFormat;

  static final Uint8List _png = Uint8List.fromList(
    img.encodePng(
      img.Image(width: 24, height: 34)
        ..clear(img.ColorRgb8(250, 250, 250)),
    ),
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
    lastTemplate = settings?.template;
    lastFormat = imageFormat;
    if (failing) throw Exception('panne simulée');
    return InvoiceImageResult(
      pages: List<Uint8List>.generate(pageCount, (_) => _png),
      format: imageFormat ?? DocumentImageFormat.a4,
      forcedA4: forcedA4,
    );
  }
}

Invoice _invoice() => Invoice(
      id: '20261012093000',
      clientName: 'Aïssatou Diop',
      createdAt: DateTime(2026, 10, 12, 9, 30),
      items: [
        InvoiceItem(id: 'i1', name: 'Riz parfumé', quantity: 2, unitPrice: 1500),
      ],
      notes: 'Livraison lundi',
    );

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRenderer renderer,
}) async {
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: ShareInvoiceScreen(
        invoice: _invoice(),
        imageService: renderer,
        pdfService: PdfService(),
        settingsLoader: () async => DocumentSettings.defaults(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('affiche l’aperçu généré et les choix de partage',
      (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer: renderer);

    expect(renderer.calls, 1);
    expect(find.text('Aperçu'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Modèle'), findsOneWidget);
    expect(find.text('Format de sortie'), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
    expect(find.text('Reçu thermique (58 / 80 mm)'), findsOneWidget);
    // Le PDF est le format par défaut, prévisualisé en A4.
    expect(renderer.lastFormat, DocumentImageFormat.a4);
    expect(renderer.lastTemplate, DocumentTemplate.modern);
  });

  testWidgets('changer de modèle régénère l’aperçu sans toucher aux réglages',
      (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer: renderer);

    await tester.tap(find.text('Minimal'));
    await tester.pumpAndSettle();

    expect(renderer.calls, 2);
    expect(renderer.lastTemplate, DocumentTemplate.minimal);
    // Les réglages persistés n'ont pas bougé.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('document_settings'), isNull);
  });

  testWidgets('changer le format de sortie régénère l’aperçu',
      (tester) async {
    final renderer = _FakeRenderer();
    await _pump(tester, renderer: renderer);

    await tester.tap(find.text('PNG'));
    await tester.pumpAndSettle();

    expect(renderer.calls, 2);
    // Les images suivent le réglage des paramètres (A4 par défaut).
    expect(renderer.lastFormat, DocumentImageFormat.a4);
  });

  testWidgets('plusieurs pages : une image par page', (tester) async {
    final renderer = _FakeRenderer(pageCount: 3);
    await _pump(tester, renderer: renderer);

    expect(find.text('Page 1 / 3'), findsOneWidget);
    expect(find.text('Page 3 / 3'), findsOneWidget);
  });

  testWidgets('erreur : message propre puis Réessayer relance l’aperçu',
      (tester) async {
    final renderer = _FakeRenderer(failing: true);
    await _pump(tester, renderer: renderer);

    expect(find.text('Aperçu indisponible. Vérifiez puis réessayez.'),
        findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    // Le partage est impossible tant que l'aperçu a échoué.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    renderer.failing = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.text('Réessayer'), findsNothing);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('bascule A4 annoncée à l’utilisateur', (tester) async {
    final renderer = _FakeRenderer(pageCount: 2, forcedA4: true);
    await _pump(tester, renderer: renderer);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('partagée en plusieurs pages A4'),
      findsOneWidget,
    );
  });
}
