// lib/services/pdf_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import '../models/invoice.dart';
import '../utils/formatters.dart';

class PdfService {
  static const PdfColor _blue = PdfColor(0.145, 0.388, 0.922);
  static const PdfColor _blueDark = PdfColor(0.118, 0.251, 0.686);
  static const PdfColor _dark = PdfColor(0.118, 0.165, 0.357);
  static const PdfColor _grey = PdfColor(0.392, 0.455, 0.545);
  static const PdfColor _lightBg = PdfColor(0.945, 0.961, 0.992);
  static const PdfColor _white70 = PdfColor(1.0, 1.0, 1.0, 0.7);
  static const PdfColor _archive = PdfColor(0.62, 0.62, 0.62);

  // Constantes de design
  static const double _pageMargin = 36;

  Uint8List? _cachedWatermark;
  bool _watermarkLoaded = false;

  /// Charge le logo de filigrane (assets/watermark/logo.png) une seule fois.
  Future<Uint8List?> _loadWatermark() async {
    if (_watermarkLoaded) return _cachedWatermark;
    _watermarkLoaded = true;
    try {
      final data = await rootBundle.load('assets/watermark/logo.png');
      _cachedWatermark = data.buffer.asUint8List();
    } catch (_) {
      // Le filigrane est optionnel : on continue sans lui en cas d'erreur.
      _cachedWatermark = null;
    }
    return _cachedWatermark;
  }

  // Génération PDF
  Future<Uint8List> generatePdf(Invoice invoice) async {
    final doc = pw.Document(
      title: 'Facture ${invoice.clientName}',
      author: 'Gestion de Factures',
    );

    final watermark = await _loadWatermark();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_pageMargin),
        build: (pw.Context ctx) => pw.Stack(
          children: [
            // Filigrane du logo en arrière-plan (couvre aussi le PNG/JPG)
            if (watermark != null)
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Transform.rotate(
                    angle: -0.45,
                    child: pw.Opacity(
                      opacity: 0.08,
                      child: pw.Image(pw.MemoryImage(watermark), width: 400),
                    ),
                  ),
                ),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // En-tête avec ligne de séparation
                _modernHeader(invoice),
                pw.SizedBox(height: 8),
                _divider(),
                pw.SizedBox(height: 24),

                // Section client
                _modernClientBox(invoice),
                pw.SizedBox(height: 28),

                // Tableau des articles
                _modernTable(invoice),
                pw.SizedBox(height: 24),

                // Total
                _modernTotalBox(invoice),

                if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
                  pw.SizedBox(height: 20),
                  _modernNotesBox(invoice),
                ],

                pw.Spacer(),

                // Pied de page
                _modernFooter(),
              ],
            ),
          ],
        ),
      ),
    );

    return await doc.save();
  }

  Future<Uint8List> generatePng(Invoice invoice, {double dpi = 220}) async {
    final pdf = await generatePdf(invoice);
    final page = await Printing.raster(pdf, pages: [0], dpi: dpi).first;
    return await page.toPng();
  }

  Future<Uint8List> generateJpg(Invoice invoice, {double dpi = 220}) async {
    final pngBytes = await generatePng(invoice, dpi: dpi);
    final img.Image? image = img.decodeImage(pngBytes);
    if (image == null) throw Exception('Impossible de décoder l’image PNG');
    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }

  // Méthodes de partage (sans contexte)
  Future<void> shareAsPdf(Invoice invoice) async {
    final bytes = await generatePdf(invoice);
    await _share(bytes, invoice, 'pdf', 'application/pdf');
  }

  Future<void> shareAsPng(Invoice invoice) async {
    final bytes = await generatePng(invoice);
    await _share(bytes, invoice, 'png', 'image/png');
  }

  Future<void> shareAsJpg(Invoice invoice) async {
    final bytes = await generateJpg(invoice);
    await _share(bytes, invoice, 'jpg', 'image/jpeg');
  }

  Future<void> _share(Uint8List bytes, Invoice invoice, String ext, String mime) async {
    final dir = await getTemporaryDirectory();
    final slug = invoice.clientName.replaceAll(RegExp(r'[^\w]'), '_');
    final id6 = invoice.id.length >= 6
        ? invoice.id.substring(invoice.id.length - 6)
        : invoice.id;
    final file = File('${dir.path}/facture_${slug}_$id6.$ext');
    try {
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mime)],
        subject: 'Facture – ${invoice.clientName}',
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  // -------------------- Composants PDF Modernes --------------------
  
  pw.Widget _divider() {
    return pw.Container(
      height: 3,
      width: 60,
      decoration: pw.BoxDecoration(
        color: _blue,
        borderRadius: pw.BorderRadius.circular(2),
      ),
    );
  }

  pw.Widget _modernHeader(Invoice invoice) {
    final date = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(invoice.createdAt);
    final id6 = invoice.id.length >= 6
        ? invoice.id.substring(invoice.id.length - 6)
        : invoice.id;
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('FACTURE',
                style: pw.TextStyle(
                  fontSize: 34,
                  fontWeight: pw.FontWeight.bold,
                  color: _blueDark,
                  letterSpacing: 3,
                )),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Text('RÉF: ',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: _grey,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1,
                    )),
                pw.Text('#$id6',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: _blue,
                      fontWeight: pw.FontWeight.bold,
                    )),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Container(
                  width: 5,
                  height: 5,
                  decoration: pw.BoxDecoration(
                    color: _blue,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Text(date,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: _grey,
                    )),
              ],
            ),
          ],
        ),
        _modernStatusBadge(invoice.status),
      ],
    );
  }

  pw.Widget _modernStatusBadge(InvoiceStatus status) {
    late PdfColor bg;
    late PdfColor textColor;
    switch (status) {
      case InvoiceStatus.livree:
        bg = const PdfColor(0.298, 0.686, 0.314);
        textColor = PdfColors.white;
        break;
      case InvoiceStatus.enLivraison:
        bg = const PdfColor(1.0, 0.757, 0.027);
        textColor = const PdfColor(0.2, 0.2, 0.2);
        break;
      case InvoiceStatus.enCours:
        bg = const PdfColor(0.60, 0.25, 0.25);
        textColor = PdfColors.white;
        break;
      case InvoiceStatus.archivee:
        bg = _archive;
        textColor = PdfColors.white;
        break;
    }
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(20),
      ),
      child: pw.Text(
        status.label,
        style: pw.TextStyle(
          color: textColor,
          fontWeight: pw.FontWeight.bold,
          fontSize: 11,
          letterSpacing: 1,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  pw.Widget _modernClientBox(Invoice invoice) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: const PdfColor(0.882, 0.910, 0.941)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              _initials(invoice.clientName),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: _blue,
              ),
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CLIENT',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _grey,
                    letterSpacing: 2,
                  )),
              pw.SizedBox(height: 4),
              pw.Text(invoice.clientName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: _dark,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _modernTable(Invoice invoice) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(
          color: PdfColor(0.941, 0.949, 0.961),
          width: 0.5,
        ),
        bottom: const pw.BorderSide(
          color: PdfColor(0.882, 0.910, 0.941),
        ),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FixedColumnWidth(50),
        2: const pw.FixedColumnWidth(110),
        3: const pw.FixedColumnWidth(110),
      },
      children: [
        // En-tête du tableau
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: _blue,
            borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(8)),
          ),
          children: [
            _modernTh('Article', left: true),
            _modernTh('Qté'),
            _modernTh('Prix unit.'),
            _modernTh('Sous-total'),
          ],
        ),
        // Lignes du tableau
        ...invoice.items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven
                  ? PdfColors.white
                  : const PdfColor(0.976, 0.984, 0.997),
            ),
            children: [
              _modernTd(item.name, left: true),
              _modernTd(item.quantity.toString(), center: true),
              _modernTd(formatCurrency(item.unitPrice), right: true),
              _modernTd(formatCurrency(item.subtotal), right: true, bold: true),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _modernTh(String t, {bool left = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: pw.Text(t.toUpperCase(),
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
              letterSpacing: 1,
            ),
            textAlign: left ? pw.TextAlign.left : pw.TextAlign.center),
      );

  pw.Widget _modernTd(String t,
      {bool center = false,
      bool right = false,
      bool left = false,
      bool bold = false}) {
    pw.TextAlign align = pw.TextAlign.left;
    if (center) align = pw.TextAlign.center;
    if (right) align = pw.TextAlign.right;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: pw.Text(t,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: bold ? _blue : _dark,
          ),
          textAlign: align),
    );
  }

  pw.Widget _modernTotalBox(Invoice invoice) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 290,
        padding: const pw.EdgeInsets.all(22),
        decoration: pw.BoxDecoration(
          gradient: const pw.LinearGradient(
            colors: [_blue, _blueDark],
            begin: pw.Alignment.topLeft,
            end: pw.Alignment.bottomRight,
          ),
          borderRadius: pw.BorderRadius.circular(14),
          boxShadow: [
            pw.BoxShadow(
              color: const PdfColor(0.145, 0.388, 0.922, 0.3),
              blurRadius: 12,
            ),
          ],
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('TOTAL',
                style: pw.TextStyle(
                  color: _white70,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                )),
            pw.SizedBox(height: 6),
            pw.Text(formatCurrency(invoice.total),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                )),
            pw.SizedBox(height: 8),
            pw.Container(height: 1, color: PdfColor(1.0, 1.0, 1.0, 0.2)),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Articles:',
                    style: pw.TextStyle(color: _white70, fontSize: 10)),
                pw.Text('${invoice.items.length}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    )),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Unités totales:',
                    style: pw.TextStyle(color: _white70, fontSize: 10)),
                pw.Text('${invoice.totalQuantity}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _modernNotesBox(Invoice invoice) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: const PdfColor(1.0, 0.98, 0.93),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: const PdfColor(0.98, 0.93, 0.75)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 5,
                height: 5,
                decoration: pw.BoxDecoration(
                  color: const PdfColor(0.85, 0.65, 0.1),
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text('Notes',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: _dark,
                    fontSize: 10,
                  )),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(invoice.notes!,
              style: pw.TextStyle(color: _grey, fontSize: 10)),
        ],
      ),
    );
  }

  pw.Widget _modernFooter() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor(0.925, 0.941, 0.953)),
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'Facturier Konté Bussness Services',
            style: pw.TextStyle(color: _blue, fontSize: 9, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Solution conçue par Mohamed',
            style: pw.TextStyle(color: _grey, fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }
}