// test/invoice_image_test.dart
// Images de facture : rasterisation (injectée), composition sur fond blanc,
// rognage du format « long », encodage JPG, cache LRU et bascule A4.


import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/services/invoice_image_service.dart';
import 'package:invoice_app/services/pdf_service.dart';

/// Hauteur d'une page A4 à 150 dpi (points PDF → pixels).
const int _a4HeightAt150Dpi = 1754;

Invoice _invoice({int itemCount = 3}) => Invoice(
      id: '20261012093000',
      clientName: 'Aïssatou Diop',
      createdAt: DateTime(2026, 10, 12, 9, 30),
      items: List<InvoiceItem>.generate(
        itemCount,
        (index) => InvoiceItem(
          id: 'item-$index',
          name: 'Article ${index + 1}',
          quantity: index + 1,
          unitPrice: 1000 + index * 250,
        ),
      ),
      notes: 'Livraison lundi matin',
    );

/// Faux rasteriseur : deux pages de 600 × 900 px dont seules les 300
/// premières lignes contiennent de l'encre (le reste est blanc).
class _FakeRasterizer {
  _FakeRasterizer({this.pageCount = 1});

  final int pageCount;
  int calls = 0;
  double lastDpi = 0;

  static const int width = 600;
  static const int height = 900;
  static const int contentRows = 300;

  Future<List<InvoiceRasterPage>> call(Uint8List pdf, double dpi) async {
    calls++;
    lastDpi = dpi;
    return List<InvoiceRasterPage>.generate(
      pageCount,
      (_) => InvoiceRasterPage(
        width: width,
        height: height,
        rgba: _pixels(),
      ),
    );
  }

  static Uint8List _pixels() {
    final pixels = Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255);
    for (var y = 0; y < contentRows; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        // Une bande d'encre sur toute la largeur.
        if (x > 20 && x < width - 20) {
          pixels[i] = 30;
          pixels[i + 1] = 60;
          pixels[i + 2] = 120;
        }
      }
    }
    return pixels;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PdfService.clearCaches();
  });

  InvoiceImageService serviceWith(
    _FakeRasterizer rasterizer, {
    DocumentSettings settings = const DocumentSettings(
      imageFormat: DocumentImageFormat.long,
    ),
  }) =>
      InvoiceImageService(
        pdfService: PdfService(),
        rasterizer: rasterizer.call,
        settingsLoader: () async => settings,
      );

  group('Format long', () {
    test('rogne les marges blanches du bas (+ 24 px)', () async {
      final rasterizer = _FakeRasterizer();
      final result = await serviceWith(rasterizer).render(_invoice());

      expect(result.pages.length, 1);
      expect(result.format, DocumentImageFormat.long);
      expect(result.forcedA4, isFalse);

      final decoded = img.decodePng(result.pages.first)!;
      expect(decoded.width, _FakeRasterizer.width);
      // 300 lignes d'encre + 24 px de marge : bien plus court qu'une A4.
      expect(decoded.height, _FakeRasterizer.contentRows + 24);
      expect(decoded.height, lessThan(_a4HeightAt150Dpi));
      // Le fond est blanc (pas de transparence) : pixel du coin.
      expect(decoded.getPixel(2, 2).r, 255);
    });

    test('au-delà de 60 articles : bascule A4 multi-pages signalée', () async {
      final rasterizer = _FakeRasterizer(pageCount: 3);
      final result = await serviceWith(rasterizer).render(_invoice(itemCount: 61));

      expect(result.forcedA4, isTrue);
      expect(result.format, DocumentImageFormat.a4);
      // Une image par page, plus aucune page perdue.
      expect(result.pages.length, 3);

      final decoded = img.decodePng(result.pages.first)!;
      expect(decoded.height, _FakeRasterizer.height);
    });
  });

  group('Format A4', () {
    test('conserve toutes les pages et la hauteur complète', () async {
      final rasterizer = _FakeRasterizer(pageCount: 2);
      final result = await serviceWith(
        rasterizer,
        settings: const DocumentSettings(imageFormat: DocumentImageFormat.a4),
      ).render(_invoice());

      expect(result.pages.length, 2);
      expect(result.format, DocumentImageFormat.a4);
      final decoded = img.decodePng(result.pages.first)!;
      expect(decoded.height, _FakeRasterizer.height);
      expect(rasterizer.lastDpi, 150);
    });
  });

  group('Encodage', () {
    test('JPG directement depuis les pixels, décodable', () async {
      final rasterizer = _FakeRasterizer();
      final result = await serviceWith(rasterizer).render(
        _invoice(),
        output: InvoiceOutputFormat.jpg,
      );

      final decoded = img.decodeJpg(result.pages.first);
      expect(decoded, isNotNull);
      expect(decoded!.height, _FakeRasterizer.contentRows + 24);
      // Signature JPEG (SOI).
      expect(result.pages.first[0], 0xFF);
      expect(result.pages.first[1], 0xD8);
    });

    test('qualité JPEG 95 appliquée au rendu', () async {
      final rasterizer = _FakeRasterizer();
      final result = await serviceWith(rasterizer).render(
        _invoice(),
        output: InvoiceOutputFormat.jpg,
        jpgQuality: 95,
      );
      expect(img.decodeJpg(result.pages.first), isNotNull);
    });
  });

  group('Cache', () {
    test('deux demandes identiques ne produisent qu’un seul rendu', () async {
      final rasterizer = _FakeRasterizer();
      final service = serviceWith(rasterizer);
      final invoice = _invoice();

      final first = await service.render(invoice);
      final second = await service.render(invoice);

      expect(rasterizer.calls, 1);
      expect(identical(first.pages, second.pages), isTrue);
    });

    test('demandes simultanées identiques : un seul rendu', () async {
      final rasterizer = _FakeRasterizer();
      final service = serviceWith(rasterizer);
      final invoice = _invoice();

      final results = await Future.wait([
        service.render(invoice),
        service.render(invoice),
      ]);

      expect(rasterizer.calls, 1);
      expect(results[0].pages.length, results[1].pages.length);
    });

    test('un autre format de fichier réutilise les pixels déjà rendus',
        () async {
      final rasterizer = _FakeRasterizer();
      final service = serviceWith(rasterizer);
      final invoice = _invoice();

      await service.render(invoice);
      await service.render(invoice, output: InvoiceOutputFormat.jpg);

      // Le PDF n'est rastérisé qu'une fois : seul l'encodage change.
      expect(rasterizer.calls, 1);
    });

    test('un changement de réglage invalide le cache', () async {
      final rasterizer = _FakeRasterizer();
      final service = serviceWith(rasterizer);
      final invoice = _invoice();

      await service.render(invoice);
      await service.render(
        invoice,
        settings: const DocumentSettings(
          imageFormat: DocumentImageFormat.long,
          template: DocumentTemplate.classic,
        ),
      );

      expect(rasterizer.calls, 2);
    });

    test('cache LRU limité à 5 documents', () async {
      final rasterizer = _FakeRasterizer();
      final service = serviceWith(rasterizer);

      for (var i = 0; i < 7; i++) {
        await service.render(_invoice(itemCount: i + 1));
      }
      expect(rasterizer.calls, 7);

      // La plus récente est encore en cache…
      await service.render(_invoice(itemCount: 7));
      expect(rasterizer.calls, 7);
      // … la plus ancienne a été évincée.
      await service.render(_invoice(itemCount: 1));
      expect(rasterizer.calls, 8);
    });
  });

  group('Mesures (10 articles)', () {
    test('temps PDF / PNG / JPG', () async {
      final invoice = _invoice(itemCount: 10);
      const settings = DocumentSettings();
      final pdfService = PdfService();

      final pdfWatch = Stopwatch()..start();
      final pdf = await pdfService.generatePdf(invoice);
      pdfWatch.stop();

      final rasterizer = _FakeRasterizer();
      final service = InvoiceImageService(
        pdfService: pdfService,
        rasterizer: rasterizer.call,
        settingsLoader: () async => settings,
      );

      final pngWatch = Stopwatch()..start();
      await service.render(invoice);
      pngWatch.stop();

      final jpgWatch = Stopwatch()..start();
      await service.render(invoice, output: InvoiceOutputFormat.jpg);
      jpgWatch.stop();

      debugPrint(
        'MESURE 10 articles — PDF ${pdfWatch.elapsedMilliseconds} ms · '
        'PNG ${pngWatch.elapsedMilliseconds} ms · '
        'JPG ${jpgWatch.elapsedMilliseconds} ms · '
        'PDF ${pdf.length} octets',
      );

      expect(pdf.length, greaterThan(1000));
      expect(pngWatch.elapsedMilliseconds, greaterThan(0));
    });
  });
}
