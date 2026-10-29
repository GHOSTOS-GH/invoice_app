// lib/services/invoice_image_service.dart
// Images de facture : le PDF est le SEUL moteur de rendu, les images en sont
// des rastérisations.
//
// Pipeline : PDF → Printing.raster (dpi du réglage) → pixels RGBA → isolate
// (`compute`) qui compose sur fond blanc, rogne les marges blanches du bas
// (format « long ») puis encode PNG ou JPG. Aucun décodage / encodage lourd
// sur le thread UI, et pas d'aller-retour PNG → décodage → JPG : le JPG part
// des pixels bruts.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

import '../models/document_settings.dart';
import '../models/invoice.dart';
import 'document_settings_service.dart';
import 'pdf/invoice_pdf_builder.dart';
import 'pdf_service.dart';

/// Format de fichier demandé pour le partage.
enum InvoiceOutputFormat { pdf, png, jpg }

/// Une page rastérisée par `Printing.raster` (pixels RGBA bruts).
class InvoiceRasterPage {
  const InvoiceRasterPage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

/// Une page composée sur fond blanc (pixels RGB bruts).
class InvoiceComposedPage {
  const InvoiceComposedPage({
    required this.width,
    required this.height,
    required this.rgb,
  });

  final int width;
  final int height;
  final Uint8List rgb;
}

/// Résultat d'un rendu d'image : une image encodée par page.
class InvoiceImageResult {
  const InvoiceImageResult({
    required this.pages,
    required this.format,
    required this.forcedA4,
  });

  final List<Uint8List> pages;

  /// Format réellement utilisé (peut différer du réglage si bascule en A4).
  final DocumentImageFormat format;

  /// Vrai si le format « long » a été abandonné (trop d'articles).
  final bool forcedA4;
}

/// Rastérise un PDF en pages RGBA. Injecté dans les tests.
typedef InvoiceRasterizer = Future<List<InvoiceRasterPage>> Function(
  Uint8List pdf,
  double dpi,
);

/// Contrat utilisé par les écrans (remplaçable dans les tests).
abstract class InvoiceImageRenderer {
  Future<InvoiceImageResult> render(
    Invoice invoice, {
    DocumentSettings? settings,
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output,
    int? jpgQuality,
  });
}

class _ComposeRequest {
  const _ComposeRequest({
    required this.raster,
    required this.cropBottom,
    required this.padding,
  });

  final InvoiceRasterPage raster;
  final bool cropBottom;
  final int padding;
}

class _EncodeRequest {
  const _EncodeRequest({
    required this.page,
    required this.jpeg,
    required this.quality,
  });

  final InvoiceComposedPage page;
  final bool jpeg;
  final int quality;
}

/// Compose une page sur fond blanc et rogne éventuellement le bas.
///
/// Fonction de haut niveau (isolate) : uniquement des données simples.
InvoiceComposedPage _composePage(_ComposeRequest request) {
  final raster = request.raster;
  final width = raster.width;
  final height = raster.height;
  final rgba = raster.rgba;

  var outputHeight = height;
  if (request.cropBottom) {
    final lastRow = _lastContentRow(rgba, width, height);
    if (lastRow >= 0) {
      outputHeight = (lastRow + 1 + request.padding).clamp(1, height);
    } else {
      outputHeight = (request.padding * 2).clamp(1, height);
    }
  }

  final rgb = Uint8List(width * outputHeight * 3);
  for (var y = 0; y < outputHeight; y++) {
    final rowStart = y * width * 4;
    final outStart = y * width * 3;
    for (var x = 0; x < width; x++) {
      final i = rowStart + x * 4;
      final o = outStart + x * 3;
      final alpha = rgba[i + 3];
      if (alpha == 255) {
        rgb[o] = rgba[i];
        rgb[o + 1] = rgba[i + 1];
        rgb[o + 2] = rgba[i + 2];
      } else {
        final a = alpha / 255.0;
        rgb[o] = (rgba[i] * a + 255 * (1 - a)).round().clamp(0, 255);
        rgb[o + 1] = (rgba[i + 1] * a + 255 * (1 - a)).round().clamp(0, 255);
        rgb[o + 2] = (rgba[i + 2] * a + 255 * (1 - a)).round().clamp(0, 255);
      }
    }
  }

  return InvoiceComposedPage(width: width, height: outputHeight, rgb: rgb);
}

/// Dernière ligne contenant autre chose que du blanc (-1 si page blanche).
int _lastContentRow(Uint8List rgba, int width, int height) {
  for (var y = height - 1; y >= 0; y--) {
    final rowStart = y * width * 4;
    for (var x = 0; x < width; x++) {
      final i = rowStart + x * 4;
      if (rgba[i] < 250 || rgba[i + 1] < 250 || rgba[i + 2] < 250) {
        return y;
      }
    }
  }
  return -1;
}

/// Encode une page composée en PNG ou JPG (fonction de haut niveau, isolate).
Uint8List _encodePage(_EncodeRequest request) {
  final page = request.page;
  final image = img.Image.fromBytes(
    width: page.width,
    height: page.height,
    bytes: page.rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  if (request.jpeg) {
    return Uint8List.fromList(
      img.encodeJpg(image, quality: request.quality),
    );
  }
  return Uint8List.fromList(img.encodePng(image, level: 6));
}

class _CachedDocument {
  _CachedDocument(this.pages);

  final List<InvoiceComposedPage> pages;

  /// Encodages déjà produits, par clé « png » / « jpg:85 ».
  final Map<String, List<Uint8List>> encoded = <String, List<Uint8List>>{};

  /// Mémoire occupée par les pixels composés (pour borner le cache).
  int get pixelBytes =>
      pages.fold<int>(0, (sum, page) => sum + page.rgb.lengthInBytes);
}

class InvoiceImageService implements InvoiceImageRenderer {
  InvoiceImageService({
    PdfService? pdfService,
    InvoiceRasterizer? rasterizer,
    Future<DocumentSettings> Function()? settingsLoader,
  })  : _pdfService = pdfService ?? PdfService(),
        _rasterizer = rasterizer ?? _printingRasterizer,
        _settingsLoader = settingsLoader ??
            (() async => DocumentSettingsService.settingsNotifier.value);

  /// Instance partagée : l'aperçu et le partage réutilisent le même cache.
  static final InvoiceImageService instance = InvoiceImageService();

  /// Nombre de documents conservés en mémoire.
  static const int maxCachedDocuments = 5;

  /// Plafond de sécurité (les images A4 en 200 dpi sont volumineuses).
  static const int maxCachedBytes = 48 * 1024 * 1024;

  /// Marge blanche conservée sous le contenu (format « long »), en pixels.
  static const int longBottomPadding = 24;

  /// Garde-fou mémoire : au-delà de 24 millions de pixels pour une page,
  /// la génération retombe sur [fallbackRasterDpi] (sans toucher au réglage).
  static const int maxRasterPixels = 24000000;

  /// Résolution de repli quand une page serait trop grande à rastériser.
  static const double fallbackRasterDpi = 200;

  final PdfService _pdfService;
  final InvoiceRasterizer _rasterizer;
  final Future<DocumentSettings> Function() _settingsLoader;

  final LinkedHashMap<String, _CachedDocument> _documents =
      LinkedHashMap<String, _CachedDocument>();
  final Map<String, Future<InvoiceImageResult>> _pending =
      <String, Future<InvoiceImageResult>>{};
  int _cachedBytes = 0;

  @override
  Future<InvoiceImageResult> render(
    Invoice invoice, {
    DocumentSettings? settings,
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output = InvoiceOutputFormat.png,
    int? jpgQuality,
  }) async {
    final effectiveSettings = settings ?? await _settingsLoader();
    final key = _cacheKey(
      invoice,
      effectiveSettings,
      imageFormat,
      output,
      jpgQuality,
    );
    // Deux demandes identiques simultanées ne produisent qu'un seul rendu.
    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _render(
      invoice,
      effectiveSettings,
      imageFormat: imageFormat,
      output: output,
      jpgQuality: jpgQuality,
    );
    _pending[key] = future;
    return future.whenComplete(() => _pending.remove(key));
  }

  String _cacheKey(
    Invoice invoice,
    DocumentSettings settings,
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output,
    int? jpgQuality,
  ) {
    final payload = <Object?>[
      jsonEncode(invoice.toJson()),
      jsonEncode(settings.toJson()),
      imageFormat?.name,
      output.name,
      jpgQuality,
    ].join('|');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<InvoiceImageResult> _render(
    Invoice invoice,
    DocumentSettings effectiveSettings, {
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output = InvoiceOutputFormat.png,
    int? jpgQuality,
  }) async {
    var format = imageFormat ?? effectiveSettings.imageFormat;
    var forcedA4 = false;
    if (format == DocumentImageFormat.long &&
        InvoicePdfBuilder.requiresA4(invoice, effectiveSettings)) {
      format = DocumentImageFormat.a4;
      forcedA4 = true;
    }

    final dpi = effectiveRasterDpi(
      invoice,
      effectiveSettings,
      format,
      effectiveSettings.imageQuality.dpi.toDouble(),
    );
    final quality = (jpgQuality ?? effectiveSettings.jpgQuality).clamp(70, 98);
    final encodeKey =
        output == InvoiceOutputFormat.jpg ? 'jpg:$quality' : 'png';

    final documentKey = _documentKey(invoice, effectiveSettings, format, dpi);
    var document = _lookup(documentKey);
    if (document == null) {
      document = await _buildDocument(
        invoice,
        effectiveSettings,
        format,
        dpi,
      );
      _remember(documentKey, document);
    }

    final cached = document.encoded[encodeKey];
    if (cached != null) {
      debugPrint('InvoiceImageService : cache mémoire ($encodeKey)');
      return InvoiceImageResult(
        pages: cached,
        format: format,
        forcedA4: forcedA4,
      );
    }

    final encodeWatch = Stopwatch()..start();
    final pages = <Uint8List>[];
    for (final page in document.pages) {
      pages.add(await compute(
        _encodePage,
        _EncodeRequest(
          page: page,
          jpeg: output == InvoiceOutputFormat.jpg,
          quality: quality,
        ),
      ));
    }
    encodeWatch.stop();
    debugPrint(
      'InvoiceImageService : encodage ${output.name.toUpperCase()} '
      '${encodeWatch.elapsedMilliseconds} ms (${pages.length} page(s))',
    );

    document.encoded[encodeKey] = pages;
    return InvoiceImageResult(
      pages: pages,
      format: format,
      forcedA4: forcedA4,
    );
  }

  /// Résolution réellement utilisée pour rastériser [format] : le dpi du
  /// réglage, sauf si une page dépasserait [maxRasterPixels] pixels.
  @visibleForTesting
  static double effectiveRasterDpi(
    Invoice invoice,
    DocumentSettings settings,
    DocumentImageFormat format,
    double dpi,
  ) {
    final pixels = estimatedPagePixels(invoice, settings, format, dpi);
    if (pixels <= maxRasterPixels) return dpi;
    debugPrint(
      'InvoiceImageService : page estimée à '
      '${(pixels / 1000000).toStringAsFixed(1)} Mpx en ${dpi.round()} dpi, '
      'repli à ${fallbackRasterDpi.round()} dpi pour cette génération',
    );
    return fallbackRasterDpi;
  }

  /// Pixels d'une page rastérisée (largeur × hauteur estimées, format réel).
  @visibleForTesting
  static double estimatedPagePixels(
    Invoice invoice,
    DocumentSettings settings,
    DocumentImageFormat format,
    double dpi,
  ) {
    final page = InvoicePdfBuilder.resolvePageFormat(invoice, settings, format);
    return (page.width / 72 * dpi) * (page.height / 72 * dpi);
  }

  Future<_CachedDocument> _buildDocument(
    Invoice invoice,
    DocumentSettings settings,
    DocumentImageFormat format,
    double dpi,
  ) async {
    final pdfWatch = Stopwatch()..start();
    final pdf = await _pdfService.generatePdf(
      invoice,
      settings: settings,
      imageFormat: format,
    );
    pdfWatch.stop();

    final rasterWatch = Stopwatch()..start();
    final rasters = await _rasterizer(pdf, dpi);
    rasterWatch.stop();

    final composeWatch = Stopwatch()..start();
    final pages = <InvoiceComposedPage>[];
    for (final raster in rasters) {
      pages.add(await compute(
        _composePage,
        _ComposeRequest(
          raster: raster,
          cropBottom: format == DocumentImageFormat.long,
          padding: longBottomPadding,
        ),
      ));
    }
    composeWatch.stop();

    debugPrint(
      'InvoiceImageService : PDF ${pdfWatch.elapsedMilliseconds} ms · '
      'raster ${rasterWatch.elapsedMilliseconds} ms · '
      'composition ${composeWatch.elapsedMilliseconds} ms '
      '(${invoice.items.length} article(s), ${pages.length} page(s))',
    );

    return _CachedDocument(pages);
  }

  static String _documentKey(
    Invoice invoice,
    DocumentSettings settings,
    DocumentImageFormat format,
    double dpi,
  ) {
    final payload = <Object?>[
      jsonEncode(invoice.toJson()),
      jsonEncode(settings.toJson()),
      format.name,
      dpi,
    ].join('|');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  _CachedDocument? _lookup(String key) {
    final document = _documents.remove(key);
    if (document != null) _documents[key] = document;
    return document;
  }

  void _remember(String key, _CachedDocument document) {
    final previous = _documents.remove(key);
    if (previous != null) _cachedBytes -= previous.pixelBytes;
    _documents[key] = document;
    _cachedBytes += document.pixelBytes;

    while (_documents.length > maxCachedDocuments ||
        (_cachedBytes > maxCachedBytes && _documents.length > 1)) {
      final oldest = _documents.keys.first;
      final removed = _documents.remove(oldest);
      _cachedBytes -= removed?.pixelBytes ?? 0;
    }
  }

  /// Vide le cache (tests, changement de réglages massif).
  @visibleForTesting
  void clearCache() {
    _documents.clear();
    _pending.clear();
    _cachedBytes = 0;
  }

  /// Rastérisation réelle via `Printing.raster` (toutes les pages).
  static Future<List<InvoiceRasterPage>> _printingRasterizer(
    Uint8List pdf,
    double dpi,
  ) async {
    final pages = <InvoiceRasterPage>[];
    await for (final page in Printing.raster(pdf, dpi: dpi)) {
      pages.add(
        InvoiceRasterPage(
          width: page.width,
          height: page.height,
          rgba: page.pixels,
        ),
      );
    }
    return pages;
  }
}
