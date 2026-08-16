// test/receipt_builder_test.dart
// Tests du module reçu thermique : plan de lignes (partagé aperçu /
// impression) et génération des octets ESC/POS.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/receipt_settings.dart';
import 'package:invoice_app/services/receipt_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Invoice sampleInvoice() => Invoice(
        id: '20260815123456',
        clientName: 'Client Test',
        createdAt: DateTime(2026, 8, 15, 14, 30),
        items: const [
          InvoiceItem(name: 'Coca-Cola 1.5L', quantity: 2, unitPrice: 1000),
          InvoiceItem(name: 'Riz 5 kg', quantity: 1, unitPrice: 2500),
        ],
        discount: 500,
        taxRate: 18,
      );

  group('ReceiptBuilder.buildContent', () {
    test('plan contient en-tête, métadonnées, articles et totaux', () {
      const settings = ReceiptSettings(
        shopName: 'Ma Boutique',
        cashierName: 'Admin',
      );
      final content = ReceiptBuilder.buildContent(sampleInvoice(), settings);

      final texts = content.plan
          .whereType<ReceiptLine>()
          .map((l) => l.text)
          .toList();
      final rows = content.plan.whereType<ReceiptTableRow>().toList();

      // En-tête (gras, taille double, centré)
      expect(texts, contains('MA BOUTIQUE'));

      // Métadonnées
      expect(texts, contains('Date : 15/08/2026  14:30'));
      expect(texts, contains('Facture N° : #123456'));
      expect(texts, contains('Client : Client Test'));
      expect(texts, contains('Caissier : Admin'));

      // Articles
      expect(rows.any((r) => r.name == 'Coca-Cola 1.5L'), isTrue);
      expect(rows.any((r) => r.qty == 'x2'), isTrue);
      expect(rows.any((r) => r.price == '2 000'), isTrue);

      // Totaux : sous-total 4500, remise 500, TVA 720, total 4720
      expect(texts.any((t) => t.contains('SOUS-TOTAL') && t.contains('4 500')),
          isTrue);
      expect(texts.any((t) => t.contains('REMISE') && t.contains('-500')),
          isTrue);
      expect(texts.any((t) => t.contains('TVA 18%') && t.contains('720')),
          isTrue);
      expect(texts, contains('TOTAL À PAYER'));
      expect(texts, contains('4 720 FCFA'));

      // QR actif par défaut
      expect(content.qrData, 'FACTURE #123456');
    });

    test('QR désactivé si showBarcode false', () {
      const settings = ReceiptSettings(showBarcode: false);
      final content = ReceiptBuilder.buildContent(sampleInvoice(), settings);
      expect(content.qrData, isNull);
    });

    test('sanitize supprime les emojis et remplace les puces', () {
      // L'emoji est retiré mais les espaces qui l'entourent sont conservés.
      expect(ReceiptBuilder.sanitize('Merci 😀 • à bientôt'),
          'Merci  . à bientôt');
      // Les guillemets courbes sont remplacés, « » (latin1) conservés.
      expect(ReceiptBuilder.sanitize('“Bonjour”'), '"Bonjour"');
      expect(ReceiptBuilder.sanitize('«Bonjour»'), '«Bonjour»');
    });

    test('wrapText respecte la largeur', () {
      final lines = ReceiptBuilder.wrapText(
          'Un très long nom de produit qui dépasse largement', 15);
      for (final line in lines) {
        expect(line.length <= 15, isTrue,
            reason: 'ligne trop longue : « $line »');
      }
      expect(lines.length, greaterThan(1));
    });
  });

  group('ReceiptBuilder.buildEscPosBytes', () {
    test('génère des octets non vides pour 58 mm et 80 mm', () async {
      for (final format in ReceiptPaperFormat.values) {
        final settings =
            ReceiptSettings(format: format, shopName: 'Ma Boutique');
        final content =
            ReceiptBuilder.buildContent(sampleInvoice(), settings);
        final bytes = await ReceiptBuilder.buildEscPosBytes(content);

        // Flux ESC/POS complet (positionnement + texte + découpe papier).
        expect(bytes.length, greaterThan(100),
            reason: 'flux trop court pour ${format.label}');
        expect(bytes, contains(0x1B)); // commandes ESC présentes
      }
    });
  });

  group('ReceiptBuilder logo : cache + isolate', () {
    // Petite image PNG réelle, encodée en mémoire.
    Uint8List samplePng() {
      final src = img.Image(width: 60, height: 40);
      img.fill(src, color: img.ColorRgb8(180, 60, 60));
      return Uint8List.fromList(img.encodePng(src));
    }

    test('prepareLogoCached traite le logo puis le met en cache', () async {
      final png = samplePng();

      final (logo1, png1) = await ReceiptBuilder.prepareLogoCached(
        logoBytes: png,
        logoPath: '/fake/logo.png',
        maxWidth: 200,
      );
      expect(logo1, isNotNull, reason: 'le logo doit être préparé');
      expect(png1, isNotNull, reason: 'le PNG d\'aperçu doit être encodé');

      // Second appel avec la même clé : résultat mis en cache, le
      // traitement lourd (decodeImage, copyResize, pixel par pixel) n'est
      // PAS refait — même instance retournée.
      final (logo2, png2) = await ReceiptBuilder.prepareLogoCached(
        logoBytes: png,
        logoPath: '/fake/logo.png',
        maxWidth: 200,
      );
      expect(identical(logo1, logo2), isTrue,
          reason: 'l\'image doit venir du cache');
      expect(identical(png1, png2), isTrue);
    });

    test('buildContent lit le logo depuis le cache (pas de re-traitement)',
        () {
      final dir = Directory.systemTemp.createTempSync('logo_cache_test');
      try {
        final logoFile = File('${dir.path}/logo.png');
        final src = img.Image(width: 40, height: 40);
        img.fill(src, color: img.ColorRgb8(50, 50, 50));
        logoFile.writeAsBytesSync(img.encodePng(src));

        final settings =
            ReceiptSettings(logoPath: logoFile.path, showLogo: true);
        final content1 = ReceiptBuilder.buildContent(sampleInvoice(), settings,
            logoBytes: logoFile.readAsBytesSync());
        final content2 = ReceiptBuilder.buildContent(sampleInvoice(), settings,
            logoBytes: logoFile.readAsBytesSync());

        expect(content1.logoImage, isNotNull);
        expect(content1.logoPngBytes, isNotNull);
        // Même chemin de logo → même clé de cache → même instance,
        // le traitement lourd n'est pas refait au 2e appel.
        expect(identical(content1.logoImage, content2.logoImage), isTrue);
        expect(identical(content1.logoPngBytes, content2.logoPngBytes), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
