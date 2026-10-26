// lib/services/pdf_service.dart
// Façade publique du document de facture : génération du PDF (moteur unique),
// rendu des images, partage natif (fichier seul ou lot).
//
// Le layout vit dans `lib/services/pdf/` ; les images sont produites par
// `InvoiceImageService` (rastérisation du même PDF).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/document_settings.dart';
import '../models/invoice.dart';
import 'document_settings_service.dart';
import 'invoice_image_service.dart';
import 'pdf/invoice_pdf_builder.dart';

class PdfService {
  PdfService({InvoiceImageService? imageService}) : _imageServiceOverride = imageService;

  final InvoiceImageService? _imageServiceOverride;
  final InvoicePdfBuilder _builder = const InvoicePdfBuilder();

  /// Cache des PDF déjà construits (l'aperçu puis le partage PDF réutilisent
  /// le même octet stream).
  static const int _maxCachedPdfs = 5;
  static final LinkedHashMap<String, Uint8List> _pdfCache =
      LinkedHashMap<String, Uint8List>();

  InvoiceImageService get _imageService =>
      _imageServiceOverride ?? InvoiceImageService.instance;

  // ------------------------------------------------------------- génération

  /// Construit le PDF de [invoice] (A4 par défaut, ou page haute pour le
  /// format image « long »).
  Future<Uint8List> generatePdf(
    Invoice invoice, {
    DocumentSettings? settings,
    DocumentImageFormat imageFormat = DocumentImageFormat.a4,
  }) async {
    final effective = settings ?? DocumentSettingsService.settingsNotifier.value;
    final key = _pdfKey(invoice, effective, imageFormat);

    final cached = _pdfCache.remove(key);
    if (cached != null) {
      _pdfCache[key] = cached;
      debugPrint('PdfService : PDF en cache');
      return cached;
    }

    final watch = Stopwatch()..start();
    final bytes = await _builder.build(
      invoice,
      settings: effective,
      imageFormat: imageFormat,
    );
    watch.stop();
    debugPrint(
      'PdfService : PDF ${watch.elapsedMilliseconds} ms '
      '(${invoice.items.length} article(s))',
    );

    _pdfCache[key] = bytes;
    while (_pdfCache.length > _maxCachedPdfs) {
      _pdfCache.remove(_pdfCache.keys.first);
    }
    return bytes;
  }

  static String _pdfKey(
    Invoice invoice,
    DocumentSettings settings,
    DocumentImageFormat imageFormat,
  ) {
    final payload = <Object?>[
      jsonEncode(invoice.toJson()),
      jsonEncode(settings.toJson()),
      imageFormat.name,
    ].join('|');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Première page du document en PNG (compatibilité).
  Future<Uint8List> generatePng(Invoice invoice, {DocumentSettings? settings}) async {
    final result = await _imageService.render(
      invoice,
      settings: settings,
      output: InvoiceOutputFormat.png,
    );
    return result.pages.first;
  }

  /// Première page du document en JPG (compatibilité).
  Future<Uint8List> generateJpg(Invoice invoice, {DocumentSettings? settings}) async {
    final result = await _imageService.render(
      invoice,
      settings: settings,
      output: InvoiceOutputFormat.jpg,
    );
    return result.pages.first;
  }

  /// Rend les images (une par page) pour l'aperçu et le partage.
  Future<InvoiceImageResult> renderImages(
    Invoice invoice, {
    DocumentSettings? settings,
    DocumentImageFormat? imageFormat,
    InvoiceOutputFormat output = InvoiceOutputFormat.png,
  }) =>
      _imageService.render(
        invoice,
        settings: settings,
        imageFormat: imageFormat,
        output: output,
      );

  // ---------------------------------------------------------------- partage

  Future<void> shareAsPdf(Invoice invoice, {DocumentSettings? settings}) async {
    final bytes = await generatePdf(invoice, settings: settings);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${invoiceFileName(invoice, 'pdf')}');
    await file.writeAsBytes(bytes, flush: true);
    await _shareFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      'Facture – ${invoice.clientName}',
      [file],
    );
  }

  Future<void> shareAsPng(Invoice invoice, {DocumentSettings? settings}) async {
    final result = await _imageService.render(
      invoice,
      settings: settings,
      output: InvoiceOutputFormat.png,
    );
    await shareImagePages(result.pages, invoice, 'png', 'image/png');
  }

  Future<void> shareAsJpg(Invoice invoice, {DocumentSettings? settings}) async {
    final result = await _imageService.render(
      invoice,
      settings: settings,
      output: InvoiceOutputFormat.jpg,
    );
    await shareImagePages(result.pages, invoice, 'jpg', 'image/jpeg');
  }

  /// Partage une ou plusieurs images de la MÊME facture en un seul appel.
  Future<void> shareImagePages(
    List<Uint8List> pages,
    Invoice invoice,
    String ext,
    String mime,
  ) async {
    if (pages.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final files = <File>[];
    final shared = <XFile>[];
    try {
      for (var i = 0; i < pages.length; i++) {
        final file = File(
          '${dir.path}/${invoiceFileName(
            invoice,
            ext,
            suffix: pages.length > 1 ? '_${i + 1}' : null,
          )}',
        );
        await file.writeAsBytes(pages[i], flush: true);
        files.add(file);
        shared.add(XFile(file.path, mimeType: mime));
      }
      await _shareFiles(
        shared,
        'Facture – ${invoice.clientName}',
        files,
      );
    } catch (error) {
      // Un échec d'écriture ne doit pas laisser de fichiers derrière lui.
      _scheduleDelete(files);
      rethrow;
    }
  }

  /// Partage plusieurs factures en un **seul** appel de partage natif
  /// (au lieu d'ouvrir le partage une fois par facture).
  Future<void> shareInvoicesAsPdf(List<Invoice> invoices) async {
    if (invoices.isEmpty) return;
    final settings = await DocumentSettingsService.instance.loadSettings();
    final dir = await getTemporaryDirectory();
    final files = <File>[];
    final shared = <XFile>[];
    try {
      for (var i = 0; i < invoices.length; i++) {
        final invoice = invoices[i];
        final bytes = await generatePdf(invoice, settings: settings);
        // Index suffixé pour garantir des noms uniques (même client, même
        // réf.) : les fichiers temporaires doivent être distincts.
        final file = File(
          '${dir.path}/${invoiceFileName(invoice, 'pdf', suffix: '_${i + 1}')}',
        );
        await file.writeAsBytes(bytes, flush: true);
        files.add(file);
        shared.add(XFile(file.path, mimeType: 'application/pdf'));
      }
      await _shareFiles(
        shared,
        'Factures (${invoices.length})',
        files,
      );
    } catch (error) {
      _scheduleDelete(files);
      rethrow;
    }
  }

  /// `facture_<client-slug>_<id6>.ext` (comportement historique conservé).
  static String invoiceFileName(
    Invoice invoice,
    String ext, {
    String? suffix,
  }) {
    final slug = invoice.clientName.replaceAll(RegExp(r'[^\w]'), '_');
    final id6 = invoice.id.length >= 6
        ? invoice.id.substring(invoice.id.length - 6)
        : invoice.id;
    return 'facture_${slug}_$id6${suffix ?? ''}.$ext';
  }

  Future<void> _shareFiles(
    List<XFile> files,
    String subject,
    List<File> cleanup,
  ) async {
    try {
      await Share.shareXFiles(files, subject: subject);
    } finally {
      // Suppression SANS bloquer : le spinner ne doit pas attendre cette
      // seconde, mais l'application destinataire a besoin du délai pour lire
      // les fichiers.
      _scheduleDelete(cleanup);
    }
  }

  static void _scheduleDelete(List<File> files) {
    if (files.isEmpty) return;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 1)).then((_) async {
        for (final file in files) {
          try {
            if (await file.exists()) await file.delete();
          } catch (error) {
            debugPrint('PdfService : suppression impossible ($error)');
          }
        }
      }),
    );
  }

  /// Vide les caches PDF (tests).
  @visibleForTesting
  static void clearCaches() => _pdfCache.clear();
}
