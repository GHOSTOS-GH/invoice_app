// test/screens_responsive_test.dart
// Qualité visuelle obligatoire : chaque écran est parcouru à 320 dp de large
// avec un textScaler de 1.3, en thème clair ET sombre. On vérifie :
// - aucune exception de layout (overflow),
// - aucun texte sous 12 sp,
// - des zones tactiles d'au moins 48 dp.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/main.dart' show InvoiceApp;
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/screens/history_screen.dart';
import 'package:invoice_app/screens/invoice_detail_screen.dart';
import 'package:invoice_app/screens/login_screen.dart';
import 'package:invoice_app/screens/new_invoice_screen.dart';
import 'package:invoice_app/screens/receipt_preview_screen.dart';
import 'package:invoice_app/screens/settings/appearance_page.dart';
import 'package:invoice_app/screens/settings/document_page.dart';
import 'package:invoice_app/screens/share_invoice_screen.dart';
import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/services/invoice_image_service.dart';
import 'package:invoice_app/screens/settings/backup_page.dart';
import 'package:invoice_app/screens/settings/name_history_page.dart';
import 'package:invoice_app/screens/settings/products_page.dart';
import 'package:invoice_app/screens/settings/receipt_page.dart';
import 'package:invoice_app/screens/settings/security_page.dart';
import 'package:invoice_app/screens/settings_screen.dart';
import 'package:invoice_app/screens/stats_screen.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/receipt_settings_service.dart';
import 'package:invoice_app/models/receipt_settings.dart';
import 'package:invoice_app/theme/app_theme.dart';
import 'package:invoice_app/widgets/product_grid_sheet.dart';

const Size _phone = Size(320, 760);
const double _textScale = 1.3;

const String _productsJson = '''
[
  {"id": "p1", "name": "Riz parfumé", "category": "Céréales"},
  {"id": "p2", "name": "Huile rouge", "category": "Épicerie"}
]
''';

String _invoiceJson() {
  final now = DateTime.now();
  return '''
[
  {
    "id": "20261012093000",
    "clientName": "Aïssatou Diop",
    "createdAt": "${now.toIso8601String()}",
    "items": [
      {"id": "i1", "name": "Riz parfumé", "quantity": 2, "unitPrice": 1500},
      {"id": "i2", "name": "Huile rouge", "quantity": 1, "unitPrice": 2500}
    ],
    "status": "enLivraison",
    "notes": "Livraison prévue lundi matin",
    "discount": 1000,
    "taxRate": 5
  },
  {
    "id": "20261001101500",
    "clientName": "Mamadou Diallo",
    "createdAt": "${now.subtract(const Duration(days: 2)).toIso8601String()}",
    "items": [
      {"id": "i3", "name": "Sucre", "quantity": 3, "unitPrice": 800}
    ],
    "status": "livree"
  }
]
''';
}

Invoice _sampleInvoice() => Invoice(
      id: '20261012093000',
      clientName: 'Aïssatou Diop',
      createdAt: DateTime(2026, 10, 12, 9, 30),
      items: [
        InvoiceItem(
            id: 'i1', name: 'Riz parfumé', quantity: 2, unitPrice: 1500),
        InvoiceItem(
            id: 'i2', name: 'Huile rouge', quantity: 1, unitPrice: 2500),
        InvoiceItem(id: 'i3', name: 'Savon', quantity: 4, unitPrice: 500),
      ],
      status: InvoiceStatus.enLivraison,
      notes: 'Livraison prévue lundi matin',
      discount: 1000,
      taxRate: 5,
    );

/// Rendu d'images factices : ces écrans ne doivent dépendre d'aucun plugin
/// (la rastérisation réelle exige un appareil).
class _StubImageRenderer implements InvoiceImageRenderer {
  static final Uint8List _png = Uint8List.fromList(
    img.encodePng(img.Image(width: 20, height: 28)),
  );

  @override
  Future<InvoiceImageResult> render(
    Invoice invoice, {
    DocumentSettings? settings,
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output = InvoiceOutputFormat.png,
    int? jpgQuality,
  }) async =>
      InvoiceImageResult(
        pages: [_png],
        format: imageFormat ?? DocumentImageFormat.a4,
        forcedA4: false,
      );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required bool dark,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Démontre l'arbre avant de pomper : sans cela le State de l'itération
  // précédente (mode édition, feuille ouverte) survit au changement de thème
  // et les assertions portent sur l'ancien écran.
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: MediaQuery(
        data: const MediaQueryData(
          size: _phone,
          textScaler: TextScaler.linear(_textScale),
        ),
        child: screen,
      ),
    ),
  );

  // Laisse les chargements asynchrones (repository, prefs) se terminer et les
  // animations discrètes (150–250 ms) se poser.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void _expectNoOverflow(WidgetTester tester, String screenName) {
  final exception = tester.takeException();
  if (exception is FlutterError) {
    // Diagnostic lisible quand un débordement apparaît.
    debugPrint(exception.toStringDeep());
  }
  expect(
    exception,
    isNull,
    reason: '$screenName ne doit provoquer aucun débordement à 320 dp / 1.3',
  );
}

void _expectMinFontSize(WidgetTester tester, String screenName) {
  for (final element in find.byType(Text).evaluate()) {
    final text = element.widget as Text;
    final size = text.style?.fontSize;
    if (size == null) continue;
    expect(
      size,
      greaterThanOrEqualTo(12),
      reason: '$screenName : texte « ${text.data} » à $size sp (< 12 sp)',
    );
  }
}

/// Vrai si [element] est un InkWell interne à un bouton Material (la zone
/// tactile réelle est celle du bouton, vérifiée séparément).
bool _isButtonInternalInkWell(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is ButtonStyleButton || widget is IconButton) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

void _expectTapTargets(WidgetTester tester, String screenName) {
  final finders = <Finder>[
    find.byType(InkWell),
    find.byType(IconButton),
    find.byType(TextButton),
    find.byType(FilledButton),
    find.byType(OutlinedButton),
    find.byType(ElevatedButton),
    find.byType(ListTile),
    find.byType(Checkbox),
  ];

  for (var f = 0; f < finders.length; f++) {
    final finder = finders[f];
    final skipButtonInternals = f == 0; // premier finder = InkWell
    final elements = finder.evaluate().toList();
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (skipButtonInternals && _isButtonInternalInkWell(element)) {
        continue;
      }
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      expect(
        renderObject.size.height,
        greaterThanOrEqualTo(48),
        reason: '$screenName : zone tactile de '
            '${renderObject.size.height.toStringAsFixed(1)} dp '
            '(${finder.describeMatch(Plurality.one)})',
      );
    }
  }
}

void _expectClean(WidgetTester tester, String screenName) {
  _expectNoOverflow(tester, screenName);
  _expectMinFontSize(tester, screenName);
  _expectTapTargets(tester, screenName);
}

void _resetData() {
  InvoiceRepository().resetForTests();
  HistoryService.resetCacheForTests();
}

Future<void> _walk(
  WidgetTester tester,
  String name,
  Widget screen,
) async {
  for (final dark in [false, true]) {
    SharedPreferences.setMockInitialValues({
      'invoices': _invoiceJson(),
      'products': _productsJson,
      'history_client_names': <String>['Aïssatou Diop', 'Mamadou Diallo'],
      'history_product_names': <String>['Riz parfumé', 'Huile rouge'],
      'draft_invoice': '''
      {
        "id": "draft",
        "clientName": "Aïssatou Diop",
        "createdAt": "2026-10-01T10:00:00.000",
        "items": [
          {"id": "d1", "name": "Riz parfumé", "quantity": 2, "unitPrice": 1500},
          {"id": "d2", "name": "Huile rouge", "quantity": 1, "unitPrice": 2500}
        ],
        "status": "enCours"
      }
      ''',
    });
    _resetData();

    await _pumpScreen(tester, screen, dark: dark);
    _expectClean(tester, '$name (${dark ? 'sombre' : 'clair'})');
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    ReceiptSettingsService.settingsNotifier.value = ReceiptSettings.defaults();
  });

  group('Écrans à 320 dp / textScaler 1.3', () {
    testWidgets('Login', (tester) async {
      await _walk(
        tester,
        'Connexion',
        LoginScreen(onLoginSuccess: () {}),
      );
    });

    testWidgets('Création de facture', (tester) async {
      await _walk(
        tester,
        'Nouvelle facture',
        NewInvoiceScreen(onInvoiceCreated: () {}),
      );
    });

    testWidgets('Historique', (tester) async {
      await _walk(
        tester,
        'Historique',
        HistoryScreen(onInvoiceUpdated: () {}),
      );
    });

    testWidgets('Statistiques', (tester) async {
      await _walk(tester, 'Statistiques', const StatsScreen());
    });

    testWidgets('Détail de facture', (tester) async {
      await _walk(
        tester,
        'Détail',
        InvoiceDetailScreen(invoice: _sampleInvoice(), onInvoiceUpdated: () {}),
      );
    });

    testWidgets('Paramètres', (tester) async {
      await _walk(tester, 'Paramètres', const SettingsScreen());
    });

    testWidgets('Paramètres → Clients', (tester) async {
      await _walk(
        tester,
        'Clients',
        const NameHistoryPage(kind: NameHistoryKind.clients),
      );
    });

    testWidgets('Paramètres → Historique des articles', (tester) async {
      await _walk(
        tester,
        'Historique des articles',
        const NameHistoryPage(kind: NameHistoryKind.products),
      );
    });

    testWidgets('Paramètres → Produits', (tester) async {
      await _walk(tester, 'Produits', const ProductsPage());
    });

    testWidgets('Paramètres → Sauvegarde', (tester) async {
      await _walk(tester, 'Sauvegarde', const BackupPage());
    });

    testWidgets('Paramètres → Apparence', (tester) async {
      await _walk(tester, 'Apparence', const AppearancePage());
    });

    testWidgets('Paramètres → Sécurité', (tester) async {
      await _walk(tester, 'Sécurité', const SecurityPage());
    });

    testWidgets('Paramètres → Reçu thermique', (tester) async {
      await _walk(tester, 'Reçu thermique', const ReceiptSettingsPage());
    });

    testWidgets('Paramètres → Facture (PDF & images)', (tester) async {
      await _walk(
        tester,
        'Facture (PDF & images)',
        DocumentSettingsPage(imageService: _StubImageRenderer()),
      );
    });

    testWidgets('Partager la facture', (tester) async {
      await _walk(
        tester,
        'Partager la facture',
        ShareInvoiceScreen(
          invoice: _sampleInvoice(),
          imageService: _StubImageRenderer(),
          settingsLoader: () async => DocumentSettings.defaults(),
        ),
      );
    });

    testWidgets('Aperçu du reçu', (tester) async {
      await _walk(
        tester,
        'Aperçu du reçu',
        ReceiptPreviewScreen(invoice: _sampleInvoice()),
      );
    });

    testWidgets('Sélecteur de produit', (tester) async {
      await _walk(
        tester,
        'Sélecteur de produit',
        Scaffold(body: ProductGridSheet(onProductSelected: (_) {})),
      );
    });

    testWidgets('Application complète (navigation)', (tester) async {
      await _walk(tester, 'Application', const InvoiceApp());
    });
  });

  group('Mode édition du détail', () {
    testWidgets('lisible à 320 dp en clair et sombre', (tester) async {
      for (final dark in [false, true]) {
        SharedPreferences.setMockInitialValues({
          'products': _productsJson,
        });
        _resetData();

        await _pumpScreen(
          tester,
          InvoiceDetailScreen(
            invoice: _sampleInvoice(),
            onInvoiceUpdated: () {},
          ),
          dark: dark,
        );
        await tester.tap(find.byTooltip('Modifier'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }

        expect(find.text('Modification en cours'), findsOneWidget);
        _expectClean(
            tester, 'Détail en édition (${dark ? 'sombre' : 'clair'})');
      }
    });
  });

  group('Feuille « Nouvel article »', () {
    testWidgets('lisible à 320 dp en clair et sombre', (tester) async {
      for (final dark in [false, true]) {
        SharedPreferences.setMockInitialValues({
          'products': _productsJson,
        });
        _resetData();

        await _pumpScreen(
          tester,
          NewInvoiceScreen(onInvoiceCreated: () {}),
          dark: dark,
        );
        await tester.tap(find.text('Ajouter un article'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }

        expect(find.text('Nouvel article'), findsOneWidget);
        _expectClean(
          tester,
          'Feuille nouvel article (${dark ? 'sombre' : 'clair'})',
        );
      }
    });
  });
}
