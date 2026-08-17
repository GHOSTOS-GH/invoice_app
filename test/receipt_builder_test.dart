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

      // Articles : « Coca-Cola 1.5L » (13 car.) est wrappé à 10 → la
      // quantité et le prix n'apparaissent que sur la première ligne.
      expect(rows.any((r) => r.name == 'Coca-Cola'), isTrue);
      expect(rows.any((r) => r.name == '1.5L'), isTrue);
      expect(rows.any((r) => r.qty == 'x2' && r.price == '2 000'), isTrue);
      expect(rows.any((r) => r.name == 'Riz 5 kg'), isTrue);

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

  group('tableau des articles : pas de débordement', () {
    // Règles métier FIXES (nom 10 / qté 4 / prix 8), identiques sur les
    // deux formats : la largeur utilisée est bornée par la cible. Sur le
    // papier, l'imprimante alloue plus (grille PosColumn 5/2/5) mais les
    // colonnes ne sont jamais agrandies — l'espace restant (surtout en
    // 80 mm) devient de la marge / de l'espacement.
    const expected = {
      ReceiptPaperFormat.mm58: (name: 10, qty: 4, price: 8),
      ReceiptPaperFormat.mm80: (name: 10, qty: 4, price: 8),
    };

    // Nom ≥ 25 caractères ET prix à 6 chiffres (125 000 FCFA) simultanément.
    Invoice extremeInvoice() => Invoice(
          id: '20260815123456',
          clientName: 'Client Test',
          createdAt: DateTime(2026, 8, 15, 14, 30),
          items: const [
            InvoiceItem(
              name: 'Eau minérale bouteille 1.5 litre fraîche',
              quantity: 1,
              unitPrice: 125000,
            ),
          ],
        );

    for (final format in ReceiptPaperFormat.values) {
      test('${format.label} : nom long + prix 6 chiffres tiennent en colonne',
          () async {
        final content = ReceiptBuilder.buildContent(
            extremeInvoice(), ReceiptSettings(format: format));
        final e = expected[format]!;

        // Aucun champ d'une ligne du tableau ne dépasse sa colonne : c'est
        // la garantie qu'aucune ligne wrappée/tronquée ne débordera du
        // bord du papier à l'impression (même plan pour l'aperçu).
        for (final row in content.plan.whereType<ReceiptTableRow>()) {
          expect(row.name.length <= e.name, isTrue,
              reason: 'nom « ${row.name} » (${row.name.length}) > ${e.name}');
          expect(row.qty.length <= e.qty, isTrue,
              reason: 'qté « ${row.qty} » (${row.qty.length}) > ${e.qty}');
          expect(row.price.length <= e.price, isTrue,
              reason: 'prix « ${row.price} » (${row.price.length}) > ${e.price}');
        }

        // Le prix à 6 chiffres tient intact dans la colonne prix.
        expect(
            content.plan
                .whereType<ReceiptTableRow>()
                .any((r) => r.price == '125 000'),
            isTrue,
            reason: 'le prix 125 000 doit être conservé tel quel');

        // Le nom long est wrappé sur plusieurs lignes, toutes ≤ colonne.
        expect(content.plan.whereType<ReceiptTableRow>().length, greaterThan(1),
            reason: 'le nom long doit être wrappé');

        // L'encodage ESC/POS des lignes du tableau passe sans erreur et
        // produit bien un flux non vide (positionnement + texte).
        final bytes = await ReceiptBuilder.buildEscPosBytes(content);
        expect(bytes.length, greaterThan(100));
      });
    }

    test('58 mm : prix extrême tronqué proprement, jamais de débordement',
        () {
      final invoice = Invoice(
        id: '20260815123456',
        clientName: 'Client Test',
        createdAt: DateTime(2026, 8, 15, 14, 30),
        items: const [
          InvoiceItem(name: 'Article', quantity: 1, unitPrice: 125000000000),
        ],
      );
      final content = ReceiptBuilder.buildContent(
          invoice, const ReceiptSettings(format: ReceiptPaperFormat.mm58));
      // On exclut la ligne d'en-tête (PRIX) : on vise bien le prix article.
      final price = content.plan
          .whereType<ReceiptTableRow>()
          .where((r) => !r.bold)
          .firstWhere((r) => r.price.isNotEmpty)
          .price;
      // « 125 000 000 000 » (15 car.) → espaces retirés puis tronqué à la
      // règle métier de 8 caractères (espaces inclus).
      expect(price.length, 8);
      expect(price, '12500000');
    });
  });

  group('règles métier fixes du tableau : 10 / 4 / 8 sur les deux formats',
      () {
    // Lignes d'articles uniquement (l'en-tête ARTICLE/QTÉ/PRIX est gras).
    List<ReceiptTableRow> itemRows(ReceiptContent content) => content.plan
        .whereType<ReceiptTableRow>()
        .where((r) => !r.bold)
        .toList();

    for (final format in ReceiptPaperFormat.values) {
      test('${format.label} : nom de 10 caractères pile → une seule ligne',
          () {
        final content = ReceiptBuilder.buildContent(
          Invoice(
            id: '20260815123456',
            clientName: 'Client Test',
            createdAt: DateTime(2026, 8, 15, 14, 30),
            // 10 caractères pile : doit tenir sur une seule ligne.
            items: const [
              InvoiceItem(name: 'ABCDEFGHIJ', quantity: 1, unitPrice: 100),
            ],
          ),
          ReceiptSettings(format: format),
        );
        final rows = itemRows(content);
        expect(rows.length, 1,
            reason: '10 caractères tiennent sur une seule ligne (pas de wrap prématuré)');
        expect(rows.first.name, 'ABCDEFGHIJ');
        expect(rows.first.name.length, 10);
      });

      test('${format.label} : nom de 11+ caractères → wrappé proprement', () {
        final content = ReceiptBuilder.buildContent(
          Invoice(
            id: '20260815123456',
            clientName: 'Client Test',
            createdAt: DateTime(2026, 8, 15, 14, 30),
            items: const [
              InvoiceItem(name: 'ABCDEFGHIJKLMNOP', quantity: 1, unitPrice: 100),
            ],
          ),
          ReceiptSettings(format: format),
        );
        final rows = itemRows(content);
        expect(rows.length, greaterThan(1),
            reason: 'le nom de 14 caractères doit wrapper sur plusieurs lignes');
        for (final row in rows) {
          expect(row.name.length, lessThanOrEqualTo(10),
              reason: 'ligne wrappée « ${row.name} » > 10 caractères');
        }
        // Aucun caractère perdu : la concaténation reconstitue le nom.
        expect(rows.map((r) => r.name).join(), 'ABCDEFGHIJKLMNOP');
      });

      test('${format.label} : quantité à 3 chiffres (x999) non tronquée', () {
        final content = ReceiptBuilder.buildContent(
          Invoice(
            id: '20260815123456',
            clientName: 'Client Test',
            createdAt: DateTime(2026, 8, 15, 14, 30),
            items: const [
              InvoiceItem(name: 'Article', quantity: 999, unitPrice: 100),
            ],
          ),
          ReceiptSettings(format: format),
        );
        // « x999 » = 4 caractères pile = budget quantité : rien n'est coupé.
        expect(itemRows(content).first.qty, 'x999');
      });

      test('${format.label} : prix de ligne compacté pour tenir en 8 caractères',
          () {
        final content = ReceiptBuilder.buildContent(
          Invoice(
            id: '20260815123456',
            clientName: 'Client Test',
            createdAt: DateTime(2026, 8, 15, 14, 30),
            items: const [
              // Sous-total 1 250 000 : « 1 250 000 » = 9 car. avec espace →
              // _fitPrice retire l'espace : « 1250000 » (7 car.) tient en 8.
              InvoiceItem(name: 'Article', quantity: 1, unitPrice: 1250000),
            ],
          ),
          ReceiptSettings(format: format),
        );
        final price = itemRows(content).first.price;
        expect(price, '1250000');
        expect(price.length, lessThanOrEqualTo(8));
      });

      test('${format.label} : prix de ligne à 8 caractères pile conservé', () {
        final content = ReceiptBuilder.buildContent(
          Invoice(
            id: '20260815123456',
            clientName: 'Client Test',
            createdAt: DateTime(2026, 8, 15, 14, 30),
            items: const [
              // Sous-total 12 500 000 : « 12 500 000 » (10 car. avec espace)
              // → compacté : « 12500000 » = 8 caractères pile, non tronqué.
              InvoiceItem(name: 'Article', quantity: 1, unitPrice: 12500000),
            ],
          ),
          ReceiptSettings(format: format),
        );
        final price = itemRows(content).first.price;
        expect(price, '12500000');
        expect(price.length, 8);
      });

      test('${format.label} : SOUS-TOTAL et TOTAL À PAYER limités à 8 caractères',
          () {
        final content = ReceiptBuilder.buildContent(
          Invoice(
            id: '20260815123456',
            clientName: 'Client Test',
            createdAt: DateTime(2026, 8, 15, 14, 30),
            items: const [
              // Sous-total = total à payer = 12 500 000 → « 12500000 » (8).
              InvoiceItem(name: 'Article', quantity: 1, unitPrice: 12500000),
            ],
          ),
          ReceiptSettings(format: format),
        );
        final texts = content.plan
            .whereType<ReceiptLine>()
            .map((l) => l.text)
            .toList();
        expect(
            texts.any((t) => t.contains('SOUS-TOTAL') && t.contains('12500000')),
            isTrue,
            reason: 'le montant du SOUS-TOTAL doit tenir en 8 caractères');
        expect(texts, contains('12500000 FCFA'),
            reason: 'le TOTAL À PAYER doit tenir en 8 caractères');
      });
    }
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
