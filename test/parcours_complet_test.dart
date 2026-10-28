// test/parcours_complet_test.dart
// Parcours de bout en bout : lancement → connexion → création (3 articles) →
// finalisation → historique → détail → remise + TVA → total cohérent →
// partage (aperçu) → archivage → filtres → CSV → sauvegarde → restauration.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/main.dart' show InvoiceApp;
import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/history_screen.dart';
import 'package:invoice_app/services/backup_service.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_image_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/product_image_store.dart';
import 'package:invoice_app/utils/formatters.dart';

const String _productsJson = '''
[
  {"id": "p1", "name": "Riz parfumé", "category": "Céréales"},
  {"id": "p2", "name": "Huile rouge", "category": "Épicerie"},
  {"id": "p3", "name": "Savon", "category": "Hygiène"}
]
''';

/// Rendu d'images factice : la rastérisation native exige un appareil.
class _FakeRenderer implements InvoiceImageRenderer {
  static final Uint8List _png = Uint8List.fromList(
    img.encodePng(img.Image(width: 24, height: 34)),
  );

  int calls = 0;

  @override
  Future<InvoiceImageResult> render(
    Invoice invoice, {
    DocumentSettings? settings,
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output = InvoiceOutputFormat.png,
    int? jpgQuality,
  }) async {
    calls++;
    return InvoiceImageResult(
      pages: [_png],
      format: imageFormat ?? DocumentImageFormat.a4,
      forcedA4: false,
    );
  }
}

void _resetData() {
  InvoiceRepository().resetForTests();
  HistoryService.resetCacheForTests();
}

void _setSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Retour arrière via le bouton de l'AppBar (l'infobulle est en français).
Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await tester.pumpAndSettle();
}

Future<void> _addItem(
  WidgetTester tester, {
  required String product,
  required String quantity,
  required String price,
}) async {
  await tester.tap(find.byTooltip('Ajouter un article').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Appuyez pour choisir un produit'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(product));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.widgetWithText(TextField, 'Quantité *'),
    quantity,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Prix unitaire (FCFA)'),
    price,
  );
  await tester.tap(find.text('Ajouter l\'article'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  // Le plugin d'impression n'existe pas en test. Sans handler, l'appel
  // `rasterPdf` lève une MissingPluginException non capturée qui ferait
  // échouer le test : on neutralise le canal (la rastérisation ne répond
  // simplement jamais, comme sur un appareil sans moteur PDF).
  const printingChannel = MethodChannel('net.nfet.printing');

  setUp(() {
    SharedPreferences.setMockInitialValues({'products': _productsJson});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printingChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printingChannel, null);
  });

  testWidgets(
      'Parcours complet : création, détail, remise + TVA, archivage, filtres, '
      'CSV, sauvegarde et restauration', (tester) async {
    _resetData();
    _setSurface(tester);

    // ---------- Lancement + connexion ----------
    await tester.pumpWidget(const InvoiceApp());
    await tester.pump();
    expect(find.text('Accès Administrateur'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Admin');
    await tester.enterText(find.byType(TextFormField).at(1), '0000');
    await tester.tap(find.text('Se connecter'));
    await _pumpFrames(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    // ---------- Création de la facture (3 articles) ----------
    await tester.enterText(
      find.widgetWithText(TextField, 'Nom du client (optionnel)'),
      'Client Parcours',
    );
    await tester.pumpAndSettle();

    await _addItem(tester,
        product: 'Riz parfumé', quantity: '2', price: '1500');
    await _addItem(tester,
        product: 'Huile rouge', quantity: '1', price: '2500');
    await _addItem(tester, product: 'Savon', quantity: '4', price: '500');

    // Total de la facture en cours : 2×1500 + 2500 + 4×500 = 7 500.
    expect(find.text(formatCurrency(7500)), findsWidgets);

    await tester.tap(find.text('Finaliser'));
    await tester.pumpAndSettle();
    expect(find.text('Facture enregistrée avec succès !'), findsOneWidget);

    // ---------- Historique ----------
    await _pumpFrames(tester);
    expect(find.text('Client Parcours'), findsOneWidget);
    expect(find.text(formatCurrency(7500)), findsWidgets);
    final stored = InvoiceRepository().invoices.single;
    expect(stored.payableTotal, 7500);

    // ---------- Détail : remise 500 + TVA 10 % ----------
    await tester.tap(find.text('Client Parcours'));
    await tester.pumpAndSettle();
    expect(find.text('Détails'), findsWidgets);
    expect(find.text(formatCurrency(7500)), findsWidgets);

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Remise (FCFA)'),
      '500',
    );
    await tester.enterText(find.widgetWithText(TextField, 'TVA (%)'), '10');
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('Facture mise à jour'), findsOneWidget);
    // 7 500 − 500 + 10 % de 7 000 = 7 700.
    expect(find.text(formatCurrency(7700)), findsWidgets);
    expect(InvoiceRepository().invoices.single.payableTotal, 7700);

    // ---------- Total mis à jour partout ----------
    await _back(tester);
    await _pumpFrames(tester);
    expect(find.text(formatCurrency(7700)), findsWidgets);
    expect(find.text(formatCurrency(7500)), findsNothing);

    await tester.tap(find.text('Stats'));
    await _pumpFrames(tester, frames: 14);
    expect(find.text(formatCurrency(7700)), findsWidgets);

    // ---------- Partage : aperçu généré ----------
    await tester.tap(find.text('Historique'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Client Parcours'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partager'));
    // L'aperçu affiche un CircularProgressIndicator : pumpAndSettle ne
    // reviendrait jamais, on avance donc image par image.
    await _pumpFrames(tester, frames: 14);
    expect(find.text('Partager la facture'), findsOneWidget);
    // La rastérisation native (Printing.raster) n'existe pas en test : l'aperçu
    // reste en cours de génération. L'aperçu réel est couvert par le test
    // suivant, avec un moteur injecté.
    expect(find.text('Génération de l’aperçu…'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('JPG'), findsOneWidget);
    await tester.tap(find.byType(BackButton).last);
    await _pumpFrames(tester);

    // ---------- Archivage (menu « Plus d'actions ») ----------
    expect(find.text('Archiver'), findsNothing);
    await tester.tap(find.byTooltip('Plus d\'actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    expect(InvoiceRepository().invoices.single.status, InvoiceStatus.archivee);

    await _back(tester);
    await _pumpFrames(tester);

    // Filtre par statut : la facture archivée reste visible.
    // « Archivée » apparaît deux fois (puce de filtre + badge de la carte).
    await tester.tap(find.text('Archivée').first);
    await _pumpFrames(tester);
    expect(find.text('Client Parcours'), findsOneWidget);

    // ---------- Filtre par période (aujourd'hui → aujourd'hui) ----------
    final today = DateFormat('dd/MM/yyyy').format(DateTime.now());
    await tester.tap(find.text('Période'));
    await tester.pumpAndSettle();
    // Le jour courant apparaît plusieurs fois (calendrier + en-tête) : la
    // première occurrence est toujours la case du calendrier.
    final day = '${DateTime.now().day}';
    await tester.tap(find.text(day).at(0));
    await _pumpFrames(tester);
    await tester.tap(find.text(day).at(0));
    await _pumpFrames(tester);
    await tester.tap(find.text('Appliquer'));
    await _pumpFrames(tester);
    expect(find.text('$today → $today'), findsOneWidget);
    expect(find.text('Client Parcours'), findsOneWidget);

    // ---------- Export CSV (contenu) ----------
    final csv = BackupService().invoicesToCsv(InvoiceRepository().invoices);
    expect(csv, contains('Client Parcours'));
    expect(csv, contains(';7700;'));
    expect(csv, contains('Riz parfumé'));

    // ---------- Sauvegarde JSON puis restauration ----------
    // Les entrées/sorties de fichiers ET les écritures du repository
    // n'avancent pas dans la zone FakeAsync d'un test de widgets : tout ce qui
    // touche au disque ou à la file d'écriture passe par `runAsync`.
    Directory? temp;
    BackupService? backup;
    late String json;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('parcours_backup_');
      backup = BackupService(
        imageStore: ProductImageStore(documentsDirectory: () async => temp!),
        documentsDirectory: () async => temp!,
      );
      json = await backup!.createBackupJson();
    });
    addTearDown(() {
      if (temp != null && temp!.existsSync()) {
        temp!.deleteSync(recursive: true);
      }
    });

    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['backupVersion'], '2.0');
    expect((decoded['invoices'] as List).length, 1);
    expect(json, contains('Client Parcours'));
    expect(json, contains('"documentSettings"'));

    await tester.runAsync(() => InvoiceRepository().replaceAll([]));
    await _pumpFrames(tester);
    expect(find.text('Client Parcours'), findsNothing);

    final restored = await tester.runAsync(() => backup!.restoreFromJson(json));
    expect(restored?.invoiceCount, 1);
    await _pumpFrames(tester);
    expect(InvoiceRepository().invoices.single.clientName, 'Client Parcours');
    expect(InvoiceRepository().invoices.single.payableTotal, 7700);
    expect(find.text('Client Parcours'), findsOneWidget);
  });

  testWidgets('Parcours complet : aperçu de partage généré depuis le détail',
      (tester) async {
    _resetData();
    _setSurface(tester);

    final invoice = Invoice(
      id: '20261012093000',
      clientName: 'Client Aperçu',
      createdAt: DateTime(2026, 10, 12, 9, 30),
      items: [
        InvoiceItem(
            id: 'i1', name: 'Riz parfumé', quantity: 2, unitPrice: 1500),
        InvoiceItem(
            id: 'i2', name: 'Huile rouge', quantity: 1, unitPrice: 2500),
      ],
      discount: 500,
      taxRate: 10,
    );
    await InvoiceRepository().replaceAll([invoice]);

    final renderer = _FakeRenderer();
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          onInvoiceUpdated: () {},
          imageService: renderer,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.text('Client Aperçu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();

    expect(find.text('Partager la facture'), findsOneWidget);
    expect(renderer.calls, 1);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('JPG'), findsOneWidget);
  });
}
