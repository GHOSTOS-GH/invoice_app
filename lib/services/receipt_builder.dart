// lib/services/receipt_builder.dart
// Construction du reçu thermique (ESC/POS).
//
// Deux rendus partagent exactement le même "plan" de lignes :
//  - l'impression réelle via esc_pos_utils_plus (bytes ESC/POS)
//  - l'aperçu à l'écran (police monospace, même alignement)
// Ainsi ce qui est affiché dans l'aperçu est identique à l'impression.

import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import '../models/invoice.dart';
import '../models/receipt_settings.dart';
import '../utils/formatters.dart';

enum ReceiptAlign { left, center, right }

/// Une ligne de texte simple du reçu.
class ReceiptLine {
  final String text;
  final ReceiptAlign align;
  final bool bold;
  final bool reverse;
  final bool underline;

  /// 1 = taille normale, 2 = double (largeur × hauteur sur imprimante).
  final int fontSize;

  const ReceiptLine(
    this.text, {
    this.align = ReceiptAlign.left,
    this.bold = false,
    this.reverse = false,
    this.underline = false,
    this.fontSize = 1,
  });
}

/// Une ligne du tableau des articles (nom à gauche, qté / prix à droite).
class ReceiptTableRow {
  final String name;
  final String qty;
  final String price;

  /// Vrai pour la ligne d'en-tête (ARTICLE / QTÉ / PRIX).
  final bool bold;
  const ReceiptTableRow({
    required this.name,
    required this.qty,
    required this.price,
    this.bold = false,
  });
}

/// Contenu complet du reçu : plan de lignes + logo + QR.
class ReceiptContent {
  final List<Object> plan; // ReceiptLine | ReceiptTableRow
  final ReceiptSettings settings;
  final Invoice invoice;

  /// Logo préparé (redimensionné + monochrome) pour l'impression.
  final img.Image? logoImage;

  /// Logo encodé en PNG pour l'affichage dans l'aperçu.
  final Uint8List? logoPngBytes;

  /// Données du QR code (null si désactivé).
  final String? qrData;

  const ReceiptContent({
    required this.plan,
    required this.settings,
    required this.invoice,
    this.logoImage,
    this.logoPngBytes,
    this.qrData,
  });
}

class ReceiptBuilder {
  // ------------------------------------------------------------------
  // Helpers de texte (partagés par l'aperçu et l'impression)
  // ------------------------------------------------------------------

  /// Remplace les caractères non imprimables en ESC/POS (code page
  /// CP1252 / latin1) pour que l'impression ne plante jamais.
  static String sanitize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x2022) {
        buffer.write('.'); // • → .
      } else if (rune == 0x2019 || rune == 0x2018) {
        buffer.write("'"); // ’ ‘ → '
      } else if (rune == 0x201C || rune == 0x201D) {
        buffer.write('"'); // “ ” → "
      } else if (rune < 256 && rune != 0x0A && rune != 0x0D) {
        buffer.writeCharCode(rune);
      }
      // Tout le reste (emoji, caractères non-latin1…) est ignoré.
    }
    return buffer.toString();
  }

  /// Découpe [text] en lignes de [width] caractères maximum,
  /// en respectant les espaces quand c'est possible.
  static List<String> wrapText(String text, int width) {
    final words = text
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final lines = <String>[];
    var current = '';
    for (var word in words) {
      while (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        lines.add(word.substring(0, width));
        word = word.substring(width);
      }
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > width) {
        if (current.isNotEmpty) lines.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines.isEmpty ? [''] : lines;
  }

  /// Aligne [left] à gauche et [right] à droite sur [width] caractères.
  static String padLR(String left, String right, int width) {
    final l = left.length > width - 1 ? left.substring(0, width - 1) : left;
    final r = right.length > width - 1
        ? right.substring(right.length - (width - 1))
        : right;
    final spaces = width - l.length - r.length;
    if (spaces < 1) return (l + r).substring(0, width);
    return '$l${' ' * spaces}$r';
  }

  // ------------------------------------------------------------------
  // Logo
  // ------------------------------------------------------------------

  /// Prépare le logo pour l'impression : redimensionné à [maxWidth]
  /// pixels puis converti en noir & blanc pur (seuil de luminance).
  static img.Image? prepareLogo(Uint8List? logoBytes, int maxWidth) {
    if (logoBytes == null) return null;
    try {
      final decoded = img.decodeImage(logoBytes);
      if (decoded == null) return null;
      final resized = decoded.width > maxWidth
          ? img.copyResize(decoded, width: maxWidth)
          : decoded;
      img.grayscale(resized);
      final bw = img.Image(width: resized.width, height: resized.height);
      for (var y = 0; y < resized.height; y++) {
        for (var x = 0; x < resized.width; x++) {
          final pixel = resized.getPixel(x, y);
          final lum = (pixel.r + pixel.g + pixel.b) / 3;
          bw.setPixel(x, y,
              lum > 140 ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0));
        }
      }
      return bw;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Plan du reçu
  // ------------------------------------------------------------------

  /// Construit le contenu complet du reçu (plan partagé aperçu/impression).
  static ReceiptContent buildContent(
    Invoice invoice,
    ReceiptSettings settings, {
    Uint8List? logoBytes,
  }) {
    final width = settings.format.charsPerLine;
    final plan = <Object>[];

    // Logo : préparé pour l'impression et pour l'aperçu.
    img.Image? logoImage;
    Uint8List? logoPngBytes;
    if (settings.showLogo) {
      logoImage = prepareLogo(logoBytes, settings.format == ReceiptPaperFormat.mm58 ? 200 : 320);
      if (logoImage != null) {
        try {
          logoPngBytes = Uint8List.fromList(img.encodePng(logoImage));
        } catch (_) {
          logoPngBytes = null;
        }
      }
    }

    // ---------- En-tête ----------
    final name = sanitize(settings.shopName.trim().toUpperCase());
    if (settings.showShopName && name.isNotEmpty) {
      // Taille double : on limite à la moitié de la largeur.
      for (final line in wrapText(name, width ~/ 2)) {
        plan.add(ReceiptLine(sanitize(line),
            align: ReceiptAlign.center, bold: true, fontSize: 2));
      }
    }

    final address = sanitize(settings.shopAddress.trim());
    if (settings.showAddress && address.isNotEmpty) {
      for (final line in wrapText(address, width)) {
        plan.add(ReceiptLine(sanitize(line), align: ReceiptAlign.center));
      }
    }

    final phone = sanitize(settings.shopPhone.trim());
    if (settings.showPhone && phone.isNotEmpty) {
      for (final line in wrapText(phone, width)) {
        plan.add(ReceiptLine(sanitize(line), align: ReceiptAlign.center));
      }
    }

    final ninea = sanitize(settings.shopNinea.trim());
    if (settings.showNinea && ninea.isNotEmpty) {
      for (final line in wrapText(ninea, width)) {
        plan.add(ReceiptLine(sanitize(line), align: ReceiptAlign.center));
      }
    }

    // ---------- Séparateur + métadonnées ----------
    plan.add(ReceiptLine('-' * width));
    plan.add(const ReceiptLine(''));

    final date =
        '${invoice.createdAt.day.toString().padLeft(2, '0')}/${invoice.createdAt.month.toString().padLeft(2, '0')}/${invoice.createdAt.year}';
    final time =
        '${invoice.createdAt.hour.toString().padLeft(2, '0')}:${invoice.createdAt.minute.toString().padLeft(2, '0')}';
    final id6 = invoice.id.length >= 6
        ? invoice.id.substring(invoice.id.length - 6)
        : invoice.id;

    plan.add(ReceiptLine('Date : $date  $time', align: ReceiptAlign.center));
    plan.add(ReceiptLine('Facture N° : #$id6', align: ReceiptAlign.center));
    final client = sanitize(invoice.clientName.trim());
    if (client.isNotEmpty) {
      for (final line in wrapText('Client : $client', width)) {
        plan.add(ReceiptLine(sanitize(line), align: ReceiptAlign.center));
      }
    }
    final cashier = sanitize(settings.cashierName.trim());
    if (cashier.isNotEmpty) {
      plan.add(ReceiptLine('Caissier : $cashier', align: ReceiptAlign.center));
    }

    plan.add(const ReceiptLine(''));
    plan.add(ReceiptLine('-' * width));

    // ---------- Tableau des articles ----------
    plan.add(const ReceiptTableRow(
        name: 'ARTICLE', qty: 'QTÉ', price: 'PRIX', bold: true));
    plan.add(ReceiptLine('-' * width));

    final nameWidth = settings.format == ReceiptPaperFormat.mm58 ? 15 : 22;
    for (final item in invoice.items) {
      final itemName = sanitize(item.name.trim());
      final wrapped = wrapText(itemName.isEmpty ? 'Article' : itemName, nameWidth);
      for (var i = 0; i < wrapped.length; i++) {
        plan.add(ReceiptTableRow(
          name: wrapped[i],
          qty: i == 0 ? 'x${item.quantity}' : '',
          price: i == 0 ? formatNumber(item.subtotal) : '',
        ));
      }
    }

    plan.add(ReceiptLine('-' * width));

    // ---------- Totaux ----------
    final subtotal = invoice.total;
    final discount = invoice.discount;
    final taxRate = invoice.taxRate;
    final taxAmount = invoice.taxAmount;
    final payable = invoice.payableTotal;

    plan.add(ReceiptLine(padLR('SOUS-TOTAL', formatNumber(subtotal), width)));
    if (discount > 0) {
      plan.add(
          ReceiptLine(padLR('REMISE', '-${formatNumber(discount)}', width)));
    }
    if (taxRate > 0) {
      plan.add(ReceiptLine(
          padLR('TVA ${formatNumber(taxRate)}%', formatNumber(taxAmount), width)));
    }
    plan.add(ReceiptLine('=' * width));
    plan.add(const ReceiptLine('TOTAL À PAYER',
        align: ReceiptAlign.center, bold: true, reverse: true));

    final totalText = '${formatNumber(payable)} FCFA';
    plan.add(ReceiptLine(
      totalText,
      align: ReceiptAlign.center,
      bold: true,
      fontSize: totalText.length <= width ~/ 2 ? 2 : 1,
    ));

    // ---------- Pied de page ----------
    final footer = sanitize(settings.footerMessage.trim());
    if (settings.showFooter && footer.isNotEmpty) {
      plan.add(const ReceiptLine(''));
      for (final line in wrapText(footer, width)) {
        plan.add(ReceiptLine(sanitize(line), align: ReceiptAlign.center));
      }
    }

    // ---------- QR code ----------
    String? qrData;
    if (settings.showBarcode) {
      qrData = 'FACTURE #$id6';
    }

    return ReceiptContent(
      plan: plan,
      settings: settings,
      invoice: invoice,
      logoImage: logoImage,
      logoPngBytes: logoPngBytes,
      qrData: qrData,
    );
  }

  // ------------------------------------------------------------------
  // Encodage ESC/POS
  // ------------------------------------------------------------------

  /// Génère les octets ESC/POS du reçu (prêt pour writeBytes).
  static Future<List<int>> buildEscPosBytes(ReceiptContent content) async {
    final settings = content.settings;
    final profile = await CapabilityProfile.load();
    final generator = Generator(
      settings.format == ReceiptPaperFormat.mm58
          ? PaperSize.mm58
          : PaperSize.mm80,
      profile,
    );

    final bytes = <int>[];

    // Logo en début de ticket.
    if (content.logoImage != null) {
      bytes.addAll(generator.imageRaster(content.logoImage!));
      bytes.addAll(generator.feed(1));
    }

    for (final item in content.plan) {
      if (item is ReceiptLine) {
        if (item.text.trim().isEmpty) {
          bytes.addAll(generator.feed(1));
          continue;
        }
        bytes.addAll(generator.text(
          item.text,
          styles: PosStyles(
            align: _posAlign(item.align),
            bold: item.bold,
            reverse: item.reverse,
            underline: item.underline,
            height: item.fontSize == 2 ? PosTextSize.size2 : PosTextSize.size1,
            width: item.fontSize == 2 ? PosTextSize.size2 : PosTextSize.size1,
            codeTable: 'CP1252',
          ),
        ));
      } else if (item is ReceiptTableRow) {
        bytes.addAll(_encodeTableRow(generator, item));
      }
    }

    // QR code de la facture (si activé).
    if (content.qrData != null) {
      bytes.addAll(generator.feed(1));
      bytes.addAll(generator.qrcode(
        content.qrData!,
        size: settings.format == ReceiptPaperFormat.mm58
            ? QRSize.size4
            : QRSize.size5,
        cor: QRCorrection.M,
      ));
    }

    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());
    return bytes;
  }

  static PosAlign _posAlign(ReceiptAlign align) {
    switch (align) {
      case ReceiptAlign.left:
        return PosAlign.left;
      case ReceiptAlign.center:
        return PosAlign.center;
      case ReceiptAlign.right:
        return PosAlign.right;
    }
  }

  /// Encodage d'une ligne du tableau en colonnes ESC/POS.
  static List<int> _encodeTableRow(Generator generator, ReceiptTableRow row) {
    return generator.row([
      PosColumn(
        text: row.name,
        width: 6,
        styles: PosStyles(
          bold: row.bold,
          align: PosAlign.left,
          codeTable: 'CP1252',
        ),
      ),
      PosColumn(
        text: row.qty,
        width: 2,
        styles: PosStyles(
          bold: row.bold,
          align: PosAlign.center,
          codeTable: 'CP1252',
        ),
      ),
      PosColumn(
        text: row.price,
        width: 4,
        styles: PosStyles(
          bold: row.bold,
          align: PosAlign.right,
          codeTable: 'CP1252',
        ),
      ),
    ]);
  }
}
