// test/receipt_settings_test.dart
// Tests d'égalité par valeur de ReceiptSettings. Sans == / hashCode,
// chaque nouvelle instance issue de fromJson() est jugée « différente »
// par ValueNotifier → notifyListeners() à chaque chargement → boucle
// infinie à l'ouverture de l'aperçu du reçu (ANR).

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_app/models/receipt_settings.dart';

void main() {
  group('ReceiptSettings : égalité par valeur', () {
    test('deux instances aux mêmes valeurs sont égales', () {
      const a = ReceiptSettings(
        shopName: 'Boutique',
        format: ReceiptPaperFormat.mm80,
        showBarcode: false,
      );
      const b = ReceiptSettings(
        shopName: 'Boutique',
        format: ReceiptPaperFormat.mm80,
        showBarcode: false,
      );
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('une différence sur un seul champ casse l\'égalité', () {
      const a = ReceiptSettings(shopName: 'Boutique');
      const b = ReceiptSettings(shopName: 'Boutique', showLogo: false);
      const c = ReceiptSettings(shopName: 'Autre');
      expect(a == b, isFalse);
      expect(a == c, isFalse);
    });

    test('fromJson produit une instance égale à l\'originale', () {
      const original = ReceiptSettings(
        shopName: 'Ma Boutique',
        shopAddress: 'Dakar',
        shopPhone: '77 123 45 67',
        shopNinea: 'SN-DKR-2024',
        footerMessage: 'Merci !',
        cashierName: 'Awa',
        logoPath: '/tmp/logo.png',
        format: ReceiptPaperFormat.mm80,
        showLogo: false,
        showShopName: false,
        showAddress: true,
        showPhone: false,
        showNinea: true,
        showFooter: false,
        showBarcode: false,
      );
      final roundTrip = ReceiptSettings.fromJson(original.toJson());
      expect(roundTrip == original, isTrue);
      expect(roundTrip.hashCode, original.hashCode);
    });

    test('l\'égalité par valeur ne dépend pas de l\'identité de l\'instance', () {
      const settings = ReceiptSettings(shopName: 'Boutique');
      final copy = settings.copyWith();
      expect(copy == settings, isTrue);
      expect(identical(copy, settings), isFalse);
    });
  });
}
