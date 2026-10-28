// lib/services/pdf/invoice_pdf_builder.dart
// Moteur de rendu UNIQUE du document de facture : le PDF. Les images (PNG /
// JPG) sont des rastérisations de ce même PDF.
//
// - `pw.MultiPage` uniquement (plus de `pw.Page`) : en-tête complet sur la
//   première page, en-tête compact ensuite, pied de page paginé, tableau dont
//   l'en-tête se répète à chaque page ;
// - le bloc totaux + notes + paiement + QR est insécable ;
// - trois modèles = trois variantes du MÊME layout ;
// - uniquement des aplats (pas de dégradé ni d'ombre floue).

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/document_settings.dart';
import '../../models/invoice.dart';
import '../../utils/formatters.dart';
import 'pdf_assets.dart';
import 'pdf_palette.dart';

class InvoicePdfBuilder {
  const InvoicePdfBuilder();

  /// Marge du document (points PDF).
  static const double pageMargin = 36;

  /// Au-delà, le format « long » bascule en A4 multi-pages.
  static const int longMaxItems = 60;
  static const double longMaxHeight = 3000;

  /// Construit le PDF complet de [invoice].
  Future<Uint8List> build(
    Invoice invoice, {
    DocumentSettings settings = const DocumentSettings(),
    DocumentImageFormat imageFormat = DocumentImageFormat.a4,
    bool compress = true,
  }) async {
    final palette = PdfPalette.fromAccent(settings.accentColor);
    final theme = await PdfAssets.theme();
    final logo = settings.hasLogo ? await PdfAssets.image(settings.logoPath) : null;
    final watermark = settings.showWatermark
        ? await PdfAssets.image(settings.logoPath)
        : null;

    final pageFormat = resolvePageFormat(invoice, settings, imageFormat);
    final layout = _InvoiceLayout(
      invoice: invoice,
      settings: settings,
      palette: palette,
      logo: logo,
      watermark: watermark,
      contentWidth: pageFormat.width - pageMargin * 2,
    );

    final document = pw.Document(
      title: 'Facture ${invoice.clientName}',
      author: settings.businessName,
      creator: 'Gestion de Factures',
      theme: theme,
      // `compress: false` n'est utilisé que par les tests (lecture du texte).
      compress: compress,
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(pageMargin),
          theme: theme,
          orientation: pw.PageOrientation.portrait,
          buildBackground: layout.background,
        ),
        header: layout.header,
        footer: layout.footer,
        build: layout.body,
      ),
    );

    return document.save();
  }

  /// Format de page effectif : A4, ou hauteur estimée par excès pour le
  /// format « long » (qui sera rogné à la rastérisation).
  static PdfPageFormat resolvePageFormat(
    Invoice invoice,
    DocumentSettings settings,
    DocumentImageFormat imageFormat,
  ) {
    if (imageFormat != DocumentImageFormat.long || requiresA4(invoice, settings)) {
      return PdfPageFormat.a4;
    }
    return PdfPageFormat(
      PdfPageFormat.a4.width,
      estimateLongHeight(invoice, settings),
    );
  }

  /// Vrai si le format « long » doit être abandonné (trop d'articles ou
  /// hauteur estimée déraisonnable).
  static bool requiresA4(Invoice invoice, DocumentSettings settings) =>
      invoice.items.length > longMaxItems ||
      estimateLongHeight(invoice, settings) > longMaxHeight;

  /// Hauteur estimée (points) du document « long », volontairement par excès.
  static double estimateLongHeight(Invoice invoice, DocumentSettings settings) {
    final hasClosing =
        (settings.showNotes && (invoice.notes?.trim().isNotEmpty ?? false)) ||
            settings.hasPaymentInfo ||
            settings.hasQr;
    return 330 + 40.0 * invoice.items.length + (hasClosing ? 120 : 0);
  }
}

/// Une variante de layout (les trois modèles partagent cette structure).
class _InvoiceLayout {
  _InvoiceLayout({
    required this.invoice,
    required this.settings,
    required this.palette,
    required this.logo,
    required this.watermark,
    required this.contentWidth,
  });

  final Invoice invoice;
  final DocumentSettings settings;
  final PdfPalette palette;
  final pw.MemoryImage? logo;
  final pw.MemoryImage? watermark;
  final double contentWidth;

  DocumentTemplate get _template => settings.template;

  String get _reference {
    final id = invoice.id;
    final short = id.length >= 6 ? id.substring(id.length - 6) : id;
    return '#$short';
  }

  String get _dateLabel => DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR')
      .format(invoice.createdAt);

  // ---------------------------------------------------------------- fond

  pw.Widget background(pw.Context context) {
    pw.Widget? layer;
    if (watermark != null) {
      layer = pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: -0.45,
                child: pw.Opacity(
                  opacity: settings.watermarkOpacity,
                  child: pw.Image(watermark!, width: 360),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Container(color: palette.white, child: layer),
    );
  }

  // ------------------------------------------------------------- en-tête

  pw.Widget header(pw.Context context) =>
      context.pageNumber == 1 ? _fullHeader() : _compactHeader();

  pw.Widget _fullHeader() {
    final onAccent = _template == DocumentTemplate.classic;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: onAccent ? const pw.EdgeInsets.all(14) : pw.EdgeInsets.zero,
      decoration: onAccent
          ? pw.BoxDecoration(color: palette.accent)
          : _template == DocumentTemplate.modern
              ? pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: palette.accent, width: 1.6),
                  ),
                )
              : null,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _identityBlock(onAccent: onAccent)),
          pw.SizedBox(width: 12),
          _metaBlock(onAccent: onAccent),
        ],
      ),
    );
  }

  pw.Widget _identityBlock({required bool onAccent}) {
    final lines = <String>[
      settings.businessAddress,
      settings.businessPhone,
      settings.businessEmail,
      settings.businessRegistration,
    ].where((line) => line.trim().isNotEmpty).toList();

    final textColor = onAccent ? palette.white : palette.ink;
    final detailColor = onAccent
        ? PdfPalette.mix(palette.white, palette.accent, 0.35)
        : palette.muted;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.Container(
            width: 44,
            height: 44,
            padding: const pw.EdgeInsets.all(3),
            alignment: pw.Alignment.center,
            decoration: onAccent
                ? pw.BoxDecoration(
                    color: palette.white,
                    borderRadius: pw.BorderRadius.circular(6),
                  )
                : null,
            child: pw.Image(logo!, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (settings.showBusinessInfo) ...[
                pw.Text(
                  settings.businessName,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: onAccent ? palette.white : palette.accentStrong,
                  ),
                ),
                if (lines.isNotEmpty) pw.SizedBox(height: 4),
                for (final line in lines)
                  pw.Text(
                    line,
                    style: pw.TextStyle(fontSize: 8.5, color: detailColor),
                  ),
              ] else if (logo == null)
                pw.Text(
                  'FACTURE',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: textColor,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _metaBlock({required bool onAccent}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          'FACTURE',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 2,
            color: onAccent ? palette.white : palette.accent,
          ),
        ),
        if (settings.showInvoiceNumber) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Réf. $_reference',
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: onAccent ? palette.white : palette.ink,
            ),
          ),
        ],
        if (settings.showDateTime) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            _dateLabel,
            style: pw.TextStyle(
              fontSize: 8.5,
              color: onAccent
                  ? PdfPalette.mix(palette.white, palette.accent, 0.35)
                  : palette.muted,
            ),
          ),
        ],
        if (settings.showStatusBadge) ...[
          pw.SizedBox(height: 6),
          _statusBadge(),
        ],
      ],
    );
  }

  pw.Widget _statusBadge() {
    final colors = PdfPalette.statusColors(invoice.status);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: pw.BoxDecoration(
        color: colors.background,
        borderRadius: pw.BorderRadius.circular(20),
      ),
      child: pw.Text(
        invoice.status.label,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.6,
          color: colors.foreground,
        ),
      ),
    );
  }

  pw.Widget _compactHeader() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: palette.border, width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'FACTURE $_reference',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.6,
              color: palette.accent,
            ),
          ),
          pw.Text(
            invoice.clientName,
            style: pw.TextStyle(fontSize: 8.5, color: palette.muted),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- contenu

  List<pw.Widget> body(pw.Context context) => <pw.Widget>[
        _clientBlock(),
        pw.SizedBox(height: 14),
        _itemsTable(),
        pw.SizedBox(height: 14),
        _closingBlock(),
      ];

  pw.Widget _clientBlock() {
    final decorated = switch (_template) {
      DocumentTemplate.modern => pw.BoxDecoration(
          color: palette.accentSoft,
          borderRadius: pw.BorderRadius.circular(10),
        ),
      DocumentTemplate.classic => pw.BoxDecoration(
          border: pw.Border.all(color: palette.border, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6),
        ),
      DocumentTemplate.minimal => null,
    };
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: decorated,
      child: pw.Row(
        children: [
          pw.Container(
            width: 30,
            height: 30,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _template == DocumentTemplate.minimal
                  ? palette.surfaceAlt
                  : palette.accent,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              _initials(invoice.clientName),
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _template == DocumentTemplate.minimal
                    ? palette.accentStrong
                    : palette.white,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'FACTURÉ À',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.4,
                    color: palette.muted,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  invoice.clientName,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _itemsTable() {
    final columns = <int, pw.TableColumnWidth>{};
    final headers = <String>[];
    final alignments = <pw.TextAlign>[];

    void addColumn(String label, pw.TableColumnWidth width, {bool right = false, bool center = false}) {
      columns[headers.length] = width;
      headers.add(label);
      alignments.add(
        right
            ? pw.TextAlign.right
            : center
                ? pw.TextAlign.center
                : pw.TextAlign.left,
      );
    }

    if (settings.showItemIndex) {
      addColumn('#', const pw.FixedColumnWidth(22), center: true);
    }
    addColumn('Article', const pw.FlexColumnWidth(1));
    addColumn('Qté', const pw.FixedColumnWidth(34), center: true);
    if (settings.showUnitPrice) {
      addColumn('Prix unit.', const pw.FixedColumnWidth(78), right: true);
    }
    addColumn('Sous-total', const pw.FixedColumnWidth(86), right: true);

    final headerDecoration = switch (_template) {
      DocumentTemplate.modern => pw.BoxDecoration(
          color: palette.accent,
          borderRadius: const pw.BorderRadius.vertical(
            top: pw.Radius.circular(5),
          ),
        ),
      DocumentTemplate.classic =>
        pw.BoxDecoration(color: palette.accentStrong),
      DocumentTemplate.minimal => null,
    };
    final headerColor = _template == DocumentTemplate.minimal
        ? palette.muted
        : palette.white;

    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: headerDecoration,
        children: [
          for (var i = 0; i < headers.length; i++)
            _cell(
              headers[i].toUpperCase(),
              bold: true,
              align: alignments[i],
              color: headerColor,
              fontSize: 7.8,
              vertical: 6,
            ),
        ],
      ),
      ...invoice.items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final zebra = _template == DocumentTemplate.modern && index.isOdd;
        final cells = <pw.Widget>[];
        if (settings.showItemIndex) {
          cells.add(_cell('${index + 1}', align: pw.TextAlign.center, color: palette.muted));
        }
        cells.add(_cell(item.name));
        cells.add(_cell('${item.quantity}', align: pw.TextAlign.center));
        if (settings.showUnitPrice) {
          cells.add(
            _cell(formatCurrency(item.unitPrice), align: pw.TextAlign.right),
          );
        }
        cells.add(
          _cell(
            formatCurrency(item.subtotal),
            align: pw.TextAlign.right,
            bold: true,
            color: palette.ink,
          ),
        );
        return pw.TableRow(
          decoration:
              zebra ? pw.BoxDecoration(color: palette.accentSoft) : null,
          children: cells,
        );
      }),
    ];

    return pw.Table(
      columnWidths: columns,
      border: _tableBorder(),
      children: rows,
    );
  }

  pw.TableBorder _tableBorder() {
    final hairline = pw.BorderSide(color: palette.border, width: 0.4);
    return switch (_template) {
      DocumentTemplate.modern => pw.TableBorder(horizontalInside: hairline),
      DocumentTemplate.classic => pw.TableBorder(
          horizontalInside: hairline,
          bottom: pw.BorderSide(color: palette.accent, width: 0.9),
        ),
      DocumentTemplate.minimal => pw.TableBorder(
          horizontalInside: hairline,
          bottom: pw.BorderSide(color: palette.ink, width: 0.8),
        ),
    };
  }

  pw.Widget _cell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? color,
    double fontSize = 8.8,
    double vertical = 5,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 5, vertical: vertical),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? palette.body,
        ),
      ),
    );
  }

  /// Bloc insécable : totaux, notes, paiement et QR restent ensemble.
  pw.Widget _closingBlock() {
    final notes = invoice.notes?.trim() ?? '';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _totalsBlock(),
        if (settings.showNotes && notes.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          _notesBlock(notes),
        ],
        if (settings.hasPaymentInfo || settings.hasQr) ...[
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (settings.hasPaymentInfo)
                pw.Expanded(child: _infoBlock('Informations de paiement')),
              if (settings.hasPaymentInfo && settings.hasQr)
                pw.SizedBox(width: 10),
              if (settings.hasQr) _qrBlock(),
            ],
          ),
        ],
      ],
    );
  }

  pw.Widget _totalsBlock() {
    final filled = _template != DocumentTemplate.minimal;
    final background = _template == DocumentTemplate.classic
        ? palette.accentStrong
        : palette.accent;
    final labelColor = filled ? palette.white : palette.muted;
    final valueColor = filled ? palette.white : palette.ink;
    final dividerColor = filled
        ? PdfPalette.mix(palette.white, background, 0.65)
        : palette.border;

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 240,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: filled ? background : palette.white,
          borderRadius: _template == DocumentTemplate.minimal
              ? null
              : pw.BorderRadius.circular(
                  _template == DocumentTemplate.modern ? 10 : 4,
                ),
          border: _template == DocumentTemplate.minimal
              ? pw.Border(
                  top: pw.BorderSide(color: palette.ink, width: 0.8),
                  bottom: pw.BorderSide(color: palette.ink, width: 0.8),
                )
              : null,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _totalLine('Sous-total', formatCurrency(invoice.subtotal),
                labelColor: labelColor, valueColor: valueColor),
            if (invoice.discountApplied > 0)
              _totalLine(
                'Remise',
                '-${formatCurrency(invoice.discountApplied)}',
                labelColor: labelColor,
                valueColor: valueColor,
              ),
            if (invoice.taxRate > 0)
              _totalLine(
                'TVA ${formatNumber(invoice.taxRate.round())} %',
                '+${formatCurrency(invoice.taxAmount)}',
                labelColor: labelColor,
                valueColor: valueColor,
              ),
            pw.SizedBox(height: 6),
            pw.Container(height: 0.6, color: dividerColor),
            pw.SizedBox(height: 6),
            pw.Text(
              'TOTAL À PAYER',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2,
                color: labelColor,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              formatCurrency(invoice.payableTotal),
              style: pw.TextStyle(
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
                color: valueColor,
              ),
            ),
            if (settings.showTotalsSummary) ...[
              pw.SizedBox(height: 6),
              pw.Container(height: 0.6, color: dividerColor),
              pw.SizedBox(height: 5),
              _totalLine(
                'Articles / Unités',
                '${invoice.items.length} / ${invoice.totalQuantity}',
                labelColor: labelColor,
                valueColor: valueColor,
                fontSize: 8,
              ),
            ],
          ],
        ),
      ),
    );
  }

  pw.Widget _totalLine(
    String label,
    String value, {
    required PdfColor labelColor,
    required PdfColor valueColor,
    double fontSize = 8.8,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: fontSize, color: labelColor),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _notesBlock(String notes) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfPalette.mix(
          palette.white,
          const PdfColor.fromInt(0xFFB45309),
          0.06,
        ),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(
          color: PdfPalette.mix(
            palette.white,
            const PdfColor.fromInt(0xFFB45309),
            0.28,
          ),
          width: 0.6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Notes',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: palette.ink,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            notes,
            style: pw.TextStyle(fontSize: 8.8, color: palette.body),
          ),
        ],
      ),
    );
  }

  pw.Widget _infoBlock(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: palette.ink,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            settings.paymentInfoText.trim(),
            style: pw.TextStyle(fontSize: 8.8, color: palette.body),
          ),
        ],
      ),
    );
  }

  pw.Widget _qrBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: palette.border, width: 0.6),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData(invoice, settings),
            width: 62,
            height: 62,
            drawText: false,
            color: palette.ink,
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Scanner pour vérifier',
            style: pw.TextStyle(fontSize: 6.5, color: palette.muted),
          ),
        ],
      ),
    );
  }

  /// Contenu du QR code (référence de la facture ou texte libre).
  static String qrData(Invoice invoice, DocumentSettings settings) {
    if (settings.qrContentMode == DocumentQrContent.custom) {
      return settings.qrCustomText.trim();
    }
    final id = invoice.id;
    final short = id.length >= 6 ? id.substring(id.length - 6) : id;
    return 'Facture #$short\n'
        'Client : ${invoice.clientName}\n'
        'Total : ${formatCurrency(invoice.payableTotal)}';
  }

  // ----------------------------------------------------------- pied de page

  pw.Widget footer(pw.Context context) {
    final line1 = settings.footerLine1.trim();
    final line2 = settings.footerLine2.trim();
    final hasText =
        settings.showFooter && (line1.isNotEmpty || line2.isNotEmpty);
    final pageLabel =
        settings.showPageNumbers ? 'Page ${context.pageNumber} / ${context.pagesCount}' : null;

    if (!hasText && pageLabel == null) return pw.SizedBox();

    final textBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (hasText && line1.isNotEmpty)
          pw.Text(
            line1,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: palette.accent,
            ),
          ),
        if (hasText && line2.isNotEmpty)
          pw.Text(
            line2,
            style: pw.TextStyle(fontSize: 7.5, color: palette.muted),
          ),
      ],
    );

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: palette.border, width: 0.6),
        ),
      ),
      child: pageLabel == null
          ? pw.Center(child: textBlock)
          : pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(child: textBlock),
                pw.SizedBox(width: 8),
                pw.Text(
                  pageLabel,
                  style: pw.TextStyle(fontSize: 7.5, color: palette.muted),
                ),
              ],
            ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
