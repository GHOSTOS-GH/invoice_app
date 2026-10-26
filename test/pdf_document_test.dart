// test/pdf_document_test.dart
// Moteur PDF : MultiPage, polices Inter, tous les réglages, cas limites
// (noms / notes très longs, caractères spéciaux, 80 articles).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/services/pdf/invoice_pdf_builder.dart';
import 'package:invoice_app/services/pdf/pdf_assets.dart';
import 'package:invoice_app/services/pdf_service.dart';
import 'package:pdf/pdf.dart';

Invoice _invoice({
  int itemCount = 1,
  String clientName = 'Aïssatou Diop',
  String? notes = 'Merci de votre confiance',
  int discount = 0,
  double taxRate = 0,
  bool longNames = false,
}) {
  final items = List<InvoiceItem>.generate(
    itemCount,
    (index) => InvoiceItem(
      id: 'item-$index',
      name: longNames
          ? 'Sac de riz parfumé « Denkan » 25 kg — lot promotionnel $index '
              'avec un libellé volontairement très long pour éprouver le retour '
              'à la ligne du tableau'
          : 'Article ${index + 1}',
      quantity: index % 3 + 1,
      unitPrice: 1250 + index * 100,
    ),
  );
  return Invoice(
    id: '20261012093000',
    clientName: clientName,
    createdAt: DateTime(2026, 10, 12, 9, 30),
    items: items,
    notes: notes,
    discount: discount,
    taxRate: taxRate,
  );
}

/// Compte les pages du PDF (les dictionnaires de page ne sont pas compressés).
int _pageCount(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page\b').allMatches(text).length;
}

Future<Uint8List> _pdf(
  Invoice invoice, {
  DocumentSettings settings = const DocumentSettings(),
  DocumentImageFormat format = DocumentImageFormat.a4,
}) =>
    const InvoicePdfBuilder().build(
      invoice,
      settings: settings,
      imageFormat: format,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  setUp(PdfAssets.resetCache);

  group('Volume et pagination', () {
    test('1 article : une seule page, PDF valide', () async {
      final bytes = await _pdf(_invoice());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(_pageCount(bytes), 1);
    });

    test('25 articles : PDF valide et paginé', () async {
      final bytes = await _pdf(_invoice(itemCount: 25));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(_pageCount(bytes), greaterThanOrEqualTo(1));
    });

    test('80 articles : plusieurs pages, aucune exception, totaux entiers',
        () async {
      final invoice = _invoice(itemCount: 80);
      final bytes = await _pdf(invoice);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(_pageCount(bytes), greaterThan(1));
      // Le total reste un entier et la facture reste cohérente.
      expect(invoice.payableTotal, invoice.subtotal);
    });
  });

  group('Cas limites de contenu', () {
    test('noms très longs : le tableau se replie sans exception', () async {
      final bytes = await _pdf(_invoice(itemCount: 12, longNames: true));
      expect(_pageCount(bytes), greaterThanOrEqualTo(1));
    });

    test('notes très longues : PDF valide', () async {
      final notes = List<String>.generate(
        40,
        (index) => 'Ligne de note numéro $index avec des précisions de livraison.',
      ).join('\n');
      final bytes = await _pdf(_invoice(notes: notes));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('caractères spéciaux (Ñ, é, œ, ’, –) avec la police Inter', () async {
      final invoice = _invoice(
        clientName: 'Ñoño Élodie Cœur-d’Alençon',
        notes: 'Livraison à l’hôtel – chambre œillet, 1er étage',
      );
      final text = String.fromCharCodes(
        await _pdf(invoice),
      );
      // La police Inter embarquée est bien utilisée (plus d'Helvetica par
      // défaut pour le texte courant).
      expect(text.contains('Inter'), isTrue);
    });

    test('remise + TVA : PDF valide', () async {
      final bytes = await _pdf(_invoice(discount: 1500, taxRate: 18));
      expect(_pageCount(bytes), greaterThanOrEqualTo(1));
    });
  });

  group('Réglages extrêmes', () {
    test('tous les interrupteurs à false : document toujours valide', () async {
      const settings = DocumentSettings(
        showLogo: false,
        showWatermark: false,
        showBusinessInfo: false,
        showInvoiceNumber: false,
        showDateTime: false,
        showStatusBadge: false,
        showItemIndex: false,
        showUnitPrice: false,
        showTotalsSummary: false,
        showNotes: false,
        showPaymentInfo: false,
        showQr: false,
        showFooter: false,
        showPageNumbers: false,
      );
      final bytes = await _pdf(
        _invoice(itemCount: 62, discount: 500, taxRate: 5),
        settings: settings,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(_pageCount(bytes), greaterThan(1));
    });

    test('tous les interrupteurs à true : document complet valide', () async {
      const settings = DocumentSettings(
        showLogo: true,
        showWatermark: true,
        showBusinessInfo: true,
        showInvoiceNumber: true,
        showDateTime: true,
        showStatusBadge: true,
        showItemIndex: true,
        showUnitPrice: true,
        showTotalsSummary: true,
        showNotes: true,
        showPaymentInfo: true,
        paymentInfoText: 'Orange Money : 77 000 00 00\nWave : 70 000 00 00',
        showQr: true,
        qrContentMode: DocumentQrContent.custom,
        qrCustomText: 'https://exemple.sn/facture/20261012093000',
        showFooter: true,
        showPageNumbers: true,
      );
      final bytes = await _pdf(
        _invoice(itemCount: 30, discount: 1000, taxRate: 10),
        settings: settings,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(_pageCount(bytes), greaterThanOrEqualTo(1));
    });
  });

  group('Modèles et formats', () {
    test('les trois modèles produisent un PDF', () async {
      for (final template in DocumentTemplate.values) {
        final bytes = await _pdf(
          _invoice(itemCount: 4),
          settings: DocumentSettings(template: template, accentColor: 0xFF0D9488),
        );
        expect(
          String.fromCharCodes(bytes.take(5)),
          '%PDF-',
          reason: 'modèle ${template.name}',
        );
      }
    });

    test('format long : une page plus courte qu’une A4 pour 3 articles',
        () async {
      final invoice = _invoice(itemCount: 3);
      final format = InvoicePdfBuilder.resolvePageFormat(
        invoice,
        const DocumentSettings(),
        DocumentImageFormat.long,
      );
      expect(format.height, lessThan(PdfPageFormat.a4.height));

      final bytes = await _pdf(invoice, format: DocumentImageFormat.long);
      expect(_pageCount(bytes), 1);
    });

    test('format long : bascule automatique en A4 au-delà de 60 articles', () {
      const settings = DocumentSettings();
      expect(
        InvoicePdfBuilder.resolvePageFormat(
          _invoice(itemCount: 61),
          settings,
          DocumentImageFormat.long,
        ).height,
        PdfPageFormat.a4.height,
      );
      expect(InvoicePdfBuilder.requiresA4(_invoice(itemCount: 61), settings),
          isTrue);
    });

    test('hauteur estimée par excès : 330 + 40 × articles (+120)', () {
      const settings = DocumentSettings();
      expect(InvoicePdfBuilder.estimateLongHeight(_invoice(itemCount: 3), settings),
          330 + 120 + 120);
      expect(
        InvoicePdfBuilder.estimateLongHeight(
          _invoice(itemCount: 3, notes: null),
          const DocumentSettings(showPaymentInfo: false, showQr: false),
        ),
        330 + 120,
      );
    });
  });

  group('Nom de fichier', () {
    test('facture_<client-slug>_<id6>.ext', () {
      expect(
        PdfService.invoiceFileName(_invoice(), 'pdf'),
        'facture_A_ssatou_Diop_093000.pdf',
      );
      expect(
        PdfService.invoiceFileName(_invoice(), 'jpg', suffix: '_2'),
        'facture_A_ssatou_Diop_093000_2.jpg',
      );
    });
  });
}
