// lib/services/receipt_builder.dart
// Construction du reçu thermique (ESC/POS).
//
// Deux rendus partagent exactement le même "plan" de lignes :
//  - l'impression réelle via esc_pos_utils_plus (bytes ESC/POS)
//  - l'aperçu à l'écran (police monospace, même alignement)
// Ainsi ce qui est affiché dans l'aperçu est identique à l'impression.

import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart' show compute;
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

/// Largeurs des colonnes du tableau des articles (nom / quantité / prix),
/// calées sur le format du papier. [nameChars], [qtyChars] et [priceChars]
/// sont les largeurs RÉELLEMENT imprimées (celles que wrapText() et la
/// troncature doivent respecter) ; [nameGrid], [qtyGrid] et [priceGrid]
/// sont les ratios PosColumn (grille de 12, somme = 12) pour l'encodage
/// ESC/POS.
class _TableColumnLayout {
  const _TableColumnLayout({
    required this.nameChars,
    required this.qtyChars,
    required this.priceChars,
    required this.nameGrid,
    required this.qtyGrid,
    required this.priceGrid,
  });

  final int nameChars;
  final int qtyChars;
  final int priceChars;
  final int nameGrid;
  final int qtyGrid;
  final int priceGrid;
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

  /// Tronque [text] à [maxChars] caractères (jamais de débordement).
  static String _fitText(String text, int maxChars) =>
      text.length <= maxChars ? text : text.substring(0, maxChars);

  /// Formate [value] (formatNumber) et garantit qu'il tient dans
  /// [maxChars] caractères : on retire d'abord les espaces de milliers,
  /// puis on tronque en dernier recours (montants extrêmes).
  static String _fitPrice(double value, int maxChars) {
    var text = formatNumber(value);
    if (text.length <= maxChars) return text;
    final compact = text.replaceAll(' ', '');
    if (compact.length <= maxChars) return compact;
    return compact.substring(0, maxChars);
  }

  // ------------------------------------------------------------------
  // Tableau des articles : largeurs de colonnes selon le format papier
  // ------------------------------------------------------------------

  /// Largeur réelle (en caractères) d'une colonne de la grille de 12,
  /// d'après la conversion interne de esc_pos_utils_plus (Generator.row :
  /// décalage de 1 point entre colonnes + 5 points d'espacement). C'est
  /// cette valeur — pas un simple ratio charsPerLine × width / 12 — que
  /// doit respecter le contenu pour ne pas déborder du papier.
  static int _columnChars(
      int gridStart, int gridWidth, ReceiptPaperFormat format) {
    final paperWidth = format == ReceiptPaperFormat.mm58 ? 384.0 : 576.0;
    final charWidth = paperWidth / format.charsPerLine;
    final fromPos = gridStart == 0 ? 0.0 : paperWidth * gridStart / 12 - 1;
    final toPos = paperWidth * (gridStart + gridWidth) / 12 - 1 - 5;
    return ((toPos - fromPos) / charWidth).floor();
  }

  /// Colonnes du tableau des articles pour [format].
  ///
  /// Cibles en caractères par format (58 mm → 32 car. : nom 16, qté 6,
  /// prix 10 ; 80 mm → 48 car. : nom 24, qté 8, prix 16), converties en
  /// ratios PosColumn (grille de 12, somme = 12). Les largeurs finales
  /// en caractères sont recalculées via [_columnChars] pour refléter
  /// exactement ce que l'imprimante alloue réellement (les ~3 caractères
  /// manquants par ligne sont perdus dans l'espacement entre colonnes).
  static _TableColumnLayout _tableLayout(ReceiptPaperFormat format) {
    // Cibles en caractères (voir spécification) :
    //  58 mm (32 car.) : nom 16, qté 6, prix 10
    //  80 mm (48 car.) : nom 24, qté 8, prix 16
    final (nameTarget, qtyTarget, priceTarget) = switch (format) {
      ReceiptPaperFormat.mm58 => (16, 6, 10),
      ReceiptPaperFormat.mm80 => (24, 8, 16),
    };
    final total = nameTarget + qtyTarget + priceTarget;

    // Ratios PosColumn en grille de 12 (somme = 12).
    final nameGrid = (nameTarget * 12 / total).round();
    final qtyGrid = (qtyTarget * 12 / total).round();
    final priceGrid = 12 - nameGrid - qtyGrid;

    return _TableColumnLayout(
      nameChars: _columnChars(0, nameGrid, format),
      qtyChars: _columnChars(nameGrid, qtyGrid, format),
      priceChars: _columnChars(nameGrid + qtyGrid, priceGrid, format),
      nameGrid: nameGrid,
      qtyGrid: qtyGrid,
      priceGrid: priceGrid,
    );
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

  /// Largeur cible (pixels) du logo selon le format du papier.
  static int logoMaxWidth(ReceiptPaperFormat format) =>
      format == ReceiptPaperFormat.mm58 ? 200 : 320;

  // ------------------------------------------------------------------
  // Cache du logo + traitement hors du thread UI (isolate)
  // ------------------------------------------------------------------
  // Le décodage + redimensionnement + binarisation du logo sont coûteux
  // et bloquaient le thread UI à chaque appel de buildContent(). Le
  // résultat est désormais mis en cache (tant que le fichier ne change
  // pas) et le premier traitement est déporté sur un isolate via
  // compute() (package:flutter/foundation.dart).

  /// Image du logo prête à imprimer, indexée par clé de cache.
  static final Map<String, img.Image> _logoImageCache = {};

  /// Logo encodé en PNG pour l'aperçu, indexé par clé de cache.
  static final Map<String, Uint8List> _logoPngCache = {};

  /// Clé de cache du logo : chemin du fichier + date de modification +
  /// largeur cible. La date de modification invalide le cache quand
  /// l'utilisateur change d'image (toujours copiée au même chemin).
  static String? _logoCacheKey(String? logoPath, int maxWidth) {
    if (logoPath == null) return null;
    try {
      final stat = File(logoPath).statSync();
      return '$logoPath|${stat.modified.millisecondsSinceEpoch}|$maxWidth';
    } catch (_) {
      // Fichier introuvable (ex. tests, logo supprimé) : clé stable
      // basée sur le chemin, le traitement sera rejoué à chaque appel.
      return '$logoPath|$maxWidth';
    }
  }

  /// Prépare le logo (décodage, redimensionnement, binarisation) sur un
  /// isolate via compute() afin de ne pas bloquer le thread UI, avec
  /// cache : le traitement lourd n'est fait qu'une fois par logo.
  ///
  /// Retourne l'image prête à imprimer et son encodage PNG (aperçu).
  /// Le cache est rempli ici puis relu par buildContent() (même clé).
  static Future<(img.Image?, Uint8List?)> prepareLogoCached({
    required Uint8List? logoBytes,
    required String? logoPath,
    required int maxWidth,
  }) async {
    if (logoBytes == null) return (null, null);
    final key = _logoCacheKey(logoPath, maxWidth);
    if (key != null) {
      final cached = _logoImageCache[key];
      if (cached != null) return (cached, _logoPngCache[key]);
    }
    // Traitement lourd sur un isolate (decodeImage, copyResize, boucle
    // pixel par pixel). Seuls des types transmissibles circulent entre
    // isolates : on renvoie les octets PNG, jamais l'objet img.Image
    // (non « sendable » : l'image contient des références circulaires).
    final pngBytes = await compute(
      _prepareLogoPngIsolate,
      (logoBytes, maxWidth),
      debugLabel: 'ReceiptBuilder.prepareLogo',
    );
    if (pngBytes == null) return (null, null);
    img.Image? image;
    try {
      // Petit PNG monochrome : le re-décodage sur le thread UI est rapide.
      image = img.decodeImage(pngBytes);
    } catch (_) {
      image = null;
    }
    if (key != null && image != null) {
      _logoImageCache[key] = image;
      _logoPngCache[key] = pngBytes;
    }
    return (image, pngBytes);
  }

  /// Point d'entrée de l'isolate : prépare le logo puis l'encode en PNG.
  static Uint8List? _prepareLogoPngIsolate((Uint8List?, int) args) {
    final image = prepareLogo(args.$1, args.$2);
    if (image == null) return null;
    try {
      return Uint8List.fromList(img.encodePng(image));
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

    // Logo : préparé pour l'impression et pour l'aperçu. Le résultat est
    // mis en cache (clé = chemin + date de modification + largeur) pour
    // ne pas refaire le traitement lourd à chaque appel de buildContent().
    img.Image? logoImage;
    Uint8List? logoPngBytes;
    if (settings.showLogo) {
      final maxWidth = logoMaxWidth(settings.format);
      final cacheKey = _logoCacheKey(settings.logoPath, maxWidth);
      if (cacheKey != null && _logoImageCache.containsKey(cacheKey)) {
        logoImage = _logoImageCache[cacheKey];
        logoPngBytes = _logoPngCache[cacheKey];
      } else {
        logoImage = prepareLogo(logoBytes, maxWidth);
        if (logoImage != null) {
          if (cacheKey != null) _logoImageCache[cacheKey] = logoImage;
          try {
            logoPngBytes = Uint8List.fromList(img.encodePng(logoImage));
            if (cacheKey != null) _logoPngCache[cacheKey] = logoPngBytes;
          } catch (_) {
            logoPngBytes = null;
          }
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

    // Largeur réelle de la colonne « nom » (calculée comme l'imprimante
    // l'alloue via PosColumn) : un nom wrappé à nameWidth tient donc
    // exactement dans la colonne sur le papier physique.
    final layout = _tableLayout(settings.format);
    for (final item in invoice.items) {
      final itemName = sanitize(item.name.trim());
      final wrapped =
          wrapText(itemName.isEmpty ? 'Article' : itemName, layout.nameChars);
      for (var i = 0; i < wrapped.length; i++) {
        plan.add(ReceiptTableRow(
          name: wrapped[i],
          qty: i == 0 ? _fitText('x${item.quantity}', layout.qtyChars) : '',
          price: i == 0 ? _fitPrice(item.subtotal, layout.priceChars) : '',
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
    final layout = _tableLayout(settings.format);

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
        bytes.addAll(_encodeTableRow(generator, item, layout));
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

  /// Encodage d'une ligne du tableau en colonnes ESC/POS. Les ratios
  /// PosColumn proviennent de [_tableLayout] : calés sur le format du
  /// papier, ils sont cohérents avec les largeurs en caractères utilisées
  /// par buildContent() (wrapText du nom + troncature qté / prix), donc
  /// aucune colonne ne déborde du bord du papier.
  static List<int> _encodeTableRow(
      Generator generator, ReceiptTableRow row, _TableColumnLayout layout) {
    return generator.row([
      PosColumn(
        text: row.name,
        width: layout.nameGrid,
        styles: PosStyles(
          bold: row.bold,
          align: PosAlign.left,
          codeTable: 'CP1252',
        ),
      ),
      PosColumn(
        text: row.qty,
        width: layout.qtyGrid,
        styles: PosStyles(
          bold: row.bold,
          align: PosAlign.center,
          codeTable: 'CP1252',
        ),
      ),
      PosColumn(
        text: row.price,
        width: layout.priceGrid,
        styles: PosStyles(
          bold: row.bold,
          align: PosAlign.right,
          codeTable: 'CP1252',
        ),
      ),
    ]);
  }
}
